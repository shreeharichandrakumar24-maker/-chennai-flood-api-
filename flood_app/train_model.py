import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
from sklearn.preprocessing import LabelEncoder

import load_data as ld

FEATURES = [
    "rainfall_mm", "rain_2d", "rain_3d", "rain_5d", "rain_7d", "rain_14d",
    "reservoir_avg_pct", "reservoir_max_pct", "reservoir_total_mcft",
    "month", "dayofyear",
]


def main():
    print("Loading datasets...")
    df = ld.build_model_dataset()
    score, labels = ld.make_labels(df)

    df = df.assign(score=score, risk=labels)
    df = df.dropna(subset=FEATURES).copy()
    df = df[df["rainfall_mm"] > 0].copy()

    print(f"Rows: {len(df)}")
    print("Label distribution:\n", df["risk"].value_counts())

    X = df[FEATURES].values
    le = LabelEncoder()
    y = le.fit_transform(df["risk"].values)

    split_year = 2018
    tr_mask = df["year"] <= split_year
    te_mask = df["year"] > split_year

    X_tr, X_te = X[tr_mask], X[te_mask]
    y_tr, y_te = y[tr_mask], y[te_mask]
    print(f"Train: {len(X_tr)}  Test: {len(X_te)}")

    model = RandomForestClassifier(
        n_estimators=300,
        max_depth=12,
        min_samples_split=5,
        min_samples_leaf=2,
        class_weight="balanced_subsample",
        random_state=42,
        n_jobs=-1,
    )
    model.fit(X_tr, y_tr)

    y_pred = model.predict(X_te)
    print("\nTest accuracy:", round(accuracy_score(y_te, y_pred), 4))
    print("\nClassification report:\n",
          classification_report(y_te, y_pred, target_names=le.classes_))
    print("Confusion matrix:\n", confusion_matrix(y_te, y_pred))

    joblib.dump({"model": model, "label_encoder": le, "features": FEATURES},
                "flood_model.joblib")
    print("\nSaved flood_model.joblib")

    importances = pd.Series(model.feature_importances_, index=FEATURES).sort_values(ascending=False)
    print("\nFeature importances:\n", importances.round(4))


if __name__ == "__main__":
    main()
