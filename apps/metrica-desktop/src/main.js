// 桌面壳层占位：状态横幅（后续切片再接 Tauri）
const banner = document.createElement("div");
banner.className = "status-banner";
banner.textContent = "Desktop shell scaffold loaded. Tauri wiring comes in the next slice.";

document.body.appendChild(banner);
