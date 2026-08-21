import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // —— 固定竖屏工具面板：640 × 960（高宽比 = 1.5，接近 4:3 竖屏 1.33）——
    // 打开即可看到全部内容，无需拖拽滚动条或改变窗口大小。
    let fixedSize = NSSize(width: 640, height: 960)
    // 使用内容区尺寸（除去标题栏高度）来算窗口原点，使整体更美观。
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    var windowFrame = self.frame
    windowFrame.size.width = fixedSize.width
    // NSWindow 的 frame 高度 = 内容高度 + 标题栏（约 28pt）
    let titleBarHeight: CGFloat = 28
    windowFrame.size.height = fixedSize.height + titleBarHeight
    // 默认放在屏幕左上角（贴近菜单栏下方），与 Windows 端 origin(10,10) 体验一致
    windowFrame.origin.x = screenFrame.minX + 10
    windowFrame.origin.y = screenFrame.maxY - windowFrame.height - 10
    self.setFrame(windowFrame, display: true)

    // 锁定最小/最大内容尺寸：防止用户拖拽标题栏或菜单调整大小
    self.contentMinSize = fixedSize
    self.contentMaxSize = fixedSize
    self.minSize = NSSize(width: fixedSize.width, height: fixedSize.height + titleBarHeight)
    self.maxSize = NSSize(width: fixedSize.width, height: fixedSize.height + titleBarHeight)

    // 移除可调整大小、缩放、全屏等 styleMask，只保留标题栏/关闭/最小化/miniaturize
    var mask: NSWindow.StyleMask = self.styleMask
    mask.remove(.resizable)
    mask.insert(.titled)
    mask.insert(.closable)
    mask.insert(.miniaturizable)
    // 禁用全屏按钮与 zoom：避免破坏竖屏布局
    self.styleMask = mask
    self.collectionBehavior.insert(.fullScreenNone)
    if let zoomBtn = self.standardWindowButton(.zoomButton) {
      zoomBtn.isEnabled = false
    }

    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
