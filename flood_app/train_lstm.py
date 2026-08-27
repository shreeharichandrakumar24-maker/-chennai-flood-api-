import json

import numpy as np
import torch
import torch.nn as nn
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
from sklearn.preprocessing import StandardScaler

import load_data as ld

WINDOW = 14
HIDDEN = 64
LAYERS = 2
DROPOUT = 0.25
EPOCHS = 60
BATCH = 128
LR = 1e-3

# Weighting factor for the classification auxiliary loss.
# Total loss = regression_loss + CLASS_LOSS_WEIGHT * classification_loss
CLASS_LOSS_WEIGHT = 0.5


class FloodLSTM(nn.Module):
    """LSTM that outputs a continuous flood-risk score (0–1).

    When ``return_logits=True`` (training only), also returns 3-class logits
    for the auxiliary classification head.  The classification head is *not*
    used at inference time, so existing callers that do not pass
    ``return_logits`` see no change in behaviour.
    """

    def __init__(self, n_features, hidden=HIDDEN, layers=LAYERS, dropout=DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(n_features, hidden, num_layers=layers,
                            batch_first=True, dropout=dropout)
        # Regression head — unchanged from original
        self.fc = nn.Sequential(
            nn.Linear(hidden, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1),
            nn.Sigmoid(),
        )
        # Classification head — 3-class logits (LOW / MODERATE / HIGH)
        self.cls_head = nn.Sequential(
            nn.Linear(hidden, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, len(ld.CLASSES)),
        )

    def forward(self, x, return_logits=False):
        """
        Parameters
        ----------
        x : Tensor of shape (batch, window, n_features)
        return_logits : bool
            If True, return (regression_score, classification_logits).
            If False (default, for inference), return only regression_score.
        """
        out, _ = self.lstm(x)
        h = out[:, -1, :]                    # last hidden state
        score = self.fc(h).squeeze(-1)       # (batch,) — regression output

        if return_logits:
            logits = self.cls_head(h)        # (batch, 3) — classification output
            return score, logits
        return score


def score_to_class(score):
    if score >= 0.60:
        return 2
    if score >= 0.35:
        return 1
    return 0


def compute_class_weights(labels):
    """Compute inverse-frequency class weights from integer labels."""
    counts = np.bincount(labels.astype(int), minlength=len(ld.CLASSES))
    total = len(labels)
    weights = total / (len(ld.CLASSES) * np.maximum(counts, 1))
    return torch.tensor(weights, dtype=torch.float32)


def main():
    torch.manual_seed(42)
    np.random.seed(42)

    print("Loading dataset...")
    model_df = ld.build_model_dataset()
    X, y, scores, dates = ld.make_lstm_sequences(model_df, window=WINDOW)
    years = dates.dt.year.values

    split_year = 2018
    tr_mask = years < split_year
    te_mask = years >= split_year
    X_tr, X_te = X[tr_mask], X[te_mask]
    y_tr, y_te = y[tr_mask], y[te_mask]
    s_tr, s_te = scores[tr_mask], scores[te_mask]

    scaler = StandardScaler()
    n, w, f = X_tr.shape
    X_tr = scaler.fit_transform(X_tr.reshape(-1, f)).reshape(n, w, f)
    n, w, f = X_te.shape
    X_te = scaler.transform(X_te.reshape(-1, f)).reshape(n, w, f)

    print(f"Train: {len(X_tr)}  Test: {len(X_te)}")
    print("Class distribution (train):",
          {ld.CLASSES[c]: int((y_tr == c).sum()) for c in range(3)})
    print("Class distribution (test):",
          {ld.CLASSES[c]: int((y_te == c).sum()) for c in range(3)})

    # --- Class weights from training data (inverse frequency) ---
    class_weights = compute_class_weights(y_tr)
    print(f"Class weights: {dict(zip(ld.CLASSES, class_weights.tolist()))}")
    cls_loss_fn = nn.CrossEntropyLoss(weight=class_weights)

    model = FloodLSTM(n_features=f)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    reg_loss_fn = nn.MSELoss()
    sched = torch.optim.lr_scheduler.StepLR(opt, step_size=15, gamma=0.5)

    train_t = torch.tensor(X_tr, dtype=torch.float32)
    train_s = torch.tensor(s_tr, dtype=torch.float32)
    train_y = torch.tensor(y_tr, dtype=torch.long)
    n_train = len(train_t)

    best_mae = float("inf")
    best_state = None
    for epoch in range(1, EPOCHS + 1):
        model.train()
        perm = torch.randperm(n_train)
        total_loss = 0.0
        for i in range(0, n_train, BATCH):
            idx = perm[i:i + BATCH]
            xb = train_t[idx]
            sb = train_s[idx]
            yb = train_y[idx]

            opt.zero_grad()
            pred_score, pred_logits = model(xb, return_logits=True)

            reg_loss = reg_loss_fn(pred_score, sb)
            cls_loss = cls_loss_fn(pred_logits, yb)
            loss = reg_loss + CLASS_LOSS_WEIGHT * cls_loss

            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            total_loss += loss.item() * len(idx)
        sched.step()

        model.eval()
        with torch.no_grad():
            val_pred = model(torch.tensor(X_te, dtype=torch.float32)).numpy()
        val_mae = float(np.mean(np.abs(val_pred - s_te)))
        if val_mae < best_mae:
            best_mae = val_mae
            best_state = {k: v.clone() for k, v in model.state_dict().items()}

        if epoch % 10 == 0 or epoch == 1:
            print(f"Epoch {epoch:3d}  loss {total_loss / n_train:.4f}  "
                  f"val_MAE {val_mae:.4f}")

    model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        pred_scores = model(torch.tensor(X_te, dtype=torch.float32)).numpy()
    pred_classes = np.array([score_to_class(s) for s in pred_scores])

    acc = accuracy_score(y_te, pred_classes)
    print(f"\nLSTM test accuracy: {acc:.4f}  (best val MAE {best_mae:.4f})")
    print("\nClassification report:\n",
          classification_report(y_te, pred_classes, target_names=ld.CLASSES,
                                zero_division=0))
    print("Confusion matrix:\n", confusion_matrix(y_te, pred_classes))

    torch.save({
        "state_dict": best_state,
        "hidden": HIDDEN,
        "layers": LAYERS,
        "dropout": DROPOUT,
        "window": WINDOW,
        "n_features": f,
        "classes": ld.CLASSES,
        "features": ld.FEATURES,
        "scaler": scaler,
        "test_accuracy": float(acc),
    }, "flood_lstm.pt")
    print("\nSaved flood_lstm.pt")

    with open("lstm_metrics.json", "w") as fh:
        json.dump({
            "accuracy": float(acc),
            "report": classification_report(y_te, pred_classes,
                                            target_names=ld.CLASSES,
                                            output_dict=True, zero_division=0),
            "confusion_matrix": confusion_matrix(y_te, pred_classes).tolist(),
        }, fh, indent=2)
    print("Saved lstm_metrics.json")


if __name__ == "__main__":
    main()
