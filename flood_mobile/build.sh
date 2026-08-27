export ANDROID_HOME="E:\\Android_SDK"
export GRADLE_USER_HOME="E:\\gradle_home"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
cd "E:/Flood prediction phase 1/flood_mobile"
flutter build apk --debug
echo "BUILD EXIT CODE: $?"
