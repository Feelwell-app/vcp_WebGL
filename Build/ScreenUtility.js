// 自動調整 Canvas 尺寸的完整解決方案

function calculateOptimalCanvasSize() {
    // 取得視窗大小
    const windowWidth = window.innerWidth;
    const windowHeight = window.innerHeight;
    
    // 原始比例 720:1280 = 9:16
    const originalRatio = 720 / 1280; // 0.5625
    
    // 計算兩種可能的尺寸
    const widthBasedHeight = windowWidth / originalRatio;  // 基於寬度計算高度
    const heightBasedWidth = windowHeight * originalRatio; // 基於高度計算寬度
    
    let canvasWidth, canvasHeight;
    
    // 選擇不會超出視窗的最大尺寸
    if (widthBasedHeight <= windowHeight) {
        // 寬度優先：使用全寬度
        canvasWidth = windowWidth;
        canvasHeight = widthBasedHeight;
    } else {
        // 高度優先：使用全高度
        canvasWidth = heightBasedWidth;
        canvasHeight = windowHeight;
    }
    
    // 加入邊距（可選）
    const margin = 20; // 20px 邊距
    canvasWidth = Math.max(320, canvasWidth - margin);   // 最小寬度 320px
    canvasHeight = Math.max(568, canvasHeight - margin); // 最小高度 568px
    
    return {
        width: Math.floor(canvasWidth),
        height: Math.floor(canvasHeight),
        ratio: canvasWidth / canvasHeight
    };
}

function setCanvasSize() {
    const canvas = document.querySelector("#unity-canvas");
    const container = document.querySelector("#unity-container");
    
    if (!canvas) return;
    
    const size = calculateOptimalCanvasSize();
    
    console.log(`設定 Canvas 尺寸: ${size.width}x${size.height} (比例: ${size.ratio.toFixed(3)})`);
    
    // 設定 Canvas 尺寸
    canvas.style.width = size.width + "px";
    canvas.style.height = size.height + "px";
    
    // 同時設定 Canvas 的實際解析度（可選，提升畫質）
    canvas.width = size.width;
    canvas.height = size.height;
    
    // 確保容器置中
    if (container && container.classList.contains('unity-desktop')) {
        container.style.left = "50%";
        container.style.top = "50%";
        container.style.transform = "translate(-50%, -50%)";
    }
}

// 替換原來的桌面設定部分
if (/iPhone|iPad|iPod|Android/i.test(navigator.userAgent)) {
    // 行動裝置：全螢幕
    var meta = document.createElement('meta');
    meta.name = 'viewport';
    meta.content = 'width=device-width, height=device-height, initial-scale=1.0, user-scalable=no, shrink-to-fit=yes';
    document.getElementsByTagName('head')[0].appendChild(meta);
    container.className = "unity-mobile";
    canvas.className = "unity-mobile";
} else {
    // 桌面：響應式尺寸
    setCanvasSize();
    
    // 監聽視窗大小變化
    window.addEventListener('resize', function() {
        // 防抖動，避免頻繁調整
        clearTimeout(window.resizeTimeout);
        window.resizeTimeout = setTimeout(setCanvasSize, 300);
    });
    
    // 全螢幕變化監聽
    document.addEventListener('fullscreenchange', function() {
        setTimeout(setCanvasSize, 100);
    });
}

// 額外的輔助函數

// 取得最適合的尺寸（考慮不同比例偏好）
function getOptimalSizeWithPreference(preference = 'balanced') {
    const windowWidth = window.innerWidth;
    const windowHeight = window.innerHeight;
    const originalRatio = 720 / 1280;
    
    switch (preference) {
        case 'width-priority':
            // 優先使用最大寬度
            return {
                width: windowWidth * 0.9,
                height: (windowWidth * 0.9) / originalRatio
            };
            
        case 'height-priority':
            // 優先使用最大高度
            return {
                width: (windowHeight * 0.9) * originalRatio,
                height: windowHeight * 0.9
            };
            
        case 'balanced':
        default:
            // 平衡模式（目前的實現）
            return calculateOptimalCanvasSize();
    }
}

// 設定特定比例
function setCustomRatio(width, height) {
    const canvas = document.querySelector("#unity-canvas");
    const windowWidth = window.innerWidth;
    const windowHeight = window.innerHeight;
    
    const targetRatio = width / height;
    const widthBasedHeight = windowWidth / targetRatio;
    const heightBasedWidth = windowHeight * targetRatio;
    
    let canvasWidth, canvasHeight;
    
    if (widthBasedHeight <= windowHeight) {
        canvasWidth = windowWidth * 0.9;
        canvasHeight = widthBasedHeight * 0.9;
    } else {
        canvasWidth = heightBasedWidth * 0.9;
        canvasHeight = windowHeight * 0.9;
    }
    
    canvas.style.width = Math.floor(canvasWidth) + "px";
    canvas.style.height = Math.floor(canvasHeight) + "px";
}

// 使用範例：
// setCustomRatio(9, 16);   // 9:16 比例
// setCustomRatio(3, 4);    // 3:4 比例
// setCustomRatio(16, 9);   // 16:9 比例