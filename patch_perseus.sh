#!/bin/bash

# Download apkeep
get_artifact_download_url () {
    local api_url="https://api.github.com/repos/$1/releases/latest"
    local result=$(curl -s $api_url | jq ".assets[] | select(.name | contains(\"$2\") and contains(\"$3\") and (contains(\".sig\") | not)) | .browser_download_url")
    echo ${result:1:-1}
}

declare -A artifacts
artifacts["apkeep"]="EFForg/apkeep apkeep-x86_64-unknown-linux-gnu"
artifacts["apktool.jar"]="iBotPeaches/Apktool apktool .jar"

# Download dependencies
for artifact in "${!artifacts[@]}"; do
    if [ ! -f "$artifact" ]; then
        echo "Downloading $artifact"
        curl -L -o "$artifact" "$(get_artifact_download_url ${artifacts[$artifact]})"
    fi
done
chmod +x apkeep

# Download Azur Lane (更新为有效链接)
if [ ! -f "com.bilibili.AzurLane.apk" ]; then
    echo "Downloading Azur Lane APK..."
    wget "https://pkg.biligame.com/games/blhx_9.5.11_0427_1_20250506_095207_d4e3f.apk" -O com.bilibili.AzurLane.apk -q || {
        echo "Failed to download APK!"
        exit 1
    }
fi

# 检查 APK 是否有效
if ! unzip -t com.bilibili.AzurLane.apk >/dev/null 2>&1; then
    echo "Error: APK file is corrupted or empty!"
    exit 1
fi

# Decompile
java -jar apktool.jar -q -f d com.bilibili.AzurLane.apk || {
    echo "Decompilation failed! Check if APK is encrypted."
    exit 1
}

# 检查关键文件是否存在
if [ ! -f "com.bilibili.AzurLane/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali" ]; then
    echo "Error: UnityPlayerActivity.smali not found! Wrong APK version?"
    exit 1
fi

# Patch with Perseus
echo "Patching..."
oncreate=$(grep -n -m 1 'onCreate' com.bilibili.AzurLane/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali | sed 's/[0-9]*\:\(.*\)/\1/')
sed -i "s#\($oncreate\)#.method private static native init(Landroid/content/Context;)V\n.end method\n\n\1#" com.bilibili.AzurLane/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali
sed -i "s#\($oncreate\)#\1\n    const-string v0, \"Perseus\"\n    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\n    invoke-static {p0}, Lcom/unity3d/player/UnityPlayerActivity;->init(Landroid/content/Context;)V\n#" com.bilibili.AzurLane/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali

# Build
java -jar apktool.jar -q -f b com.bilibili.AzurLane -o build/com.bilibili.AzurLane.patched.apk || {
    echo "Build failed!"
    exit 1
}

# Get version safely
version=$(./apkeep -a com.bilibili.AzurLane -l | tail -n 1)
[ -z "$version" ] && version="unknown"
echo "PERSEUS_VERSION=$version" >> $GITHUB_ENV

