/// ============================================================
/// 【第一性原理 · 全链路模拟审计】—— 必须跑通这张清单才准部署！
/// 目的：脱离GUI、脱离Windows Hook，用纯Dart模拟所有真实用户操作路径，
///       100% 确认"放行/吞"分支没有任何逻辑漏洞。
/// ============================================================
import '../lib/core/router.dart';
import '../lib/core/press_state.dart';
import '../lib/core/safety.dart';

// ========== 测试工具 ==========
int _pass = 0, _fail = 0;
void check(String name, bool cond, {String? detail}) {
  if (cond) {
    _pass++;
    print('  ✅ $name${detail != null ? "  ($detail)" : ""}');
  } else {
    _fail++;
    print('  ❌ $name${detail != null ? "  ($detail)" : ""}');
  }
}

// ========== 伪造 Settings + Safety ==========
class MockState {
  Map<String, dynamic> settings = {'enabled': true, 'button': 'middle'};
  SafetyState safety = SafetyState.safeDesktopText;
  double safetyTs = 0;
  final List<(String button, bool down)> actions = [];
  String? captured;
  final List<String> pressKinds = [];
}

MouseEventRouter buildRouter(MockState s, PressStateMachine press) {
  return MouseEventRouter(
    settingsGetter: () => s.settings,
    safetyGetter: () => (state: s.safety, ts: s.safetyTs),
    onAction: (button, down) {
      s.actions.add((button, down));
      if (down) {
        press.handleDown();
      } else {
        press.handleUp();
      }
    },
    onCaptureEvent: (b) {
      s.captured = b;
    },
  );
}

PressStateMachine buildPress(MockState s) {
  return PressStateMachine((kind) {
    s.pressKinds.add(kind);
    print('    [fire] $kind');
  });
}

void simulateSeconds(double sec) {
  // 用 monotonicSeconds 无法简单快进 → 改用"把safetyTs调到更早"来模拟过期，
  // 或者直接 new Timer 不现实，这里对 PressStateMachine 用真实 sleep 太粗暴，
  // 所以在下面的测试里直接测试短时间窗口（0.05s=50ms），用真实Timer让它自己跑完。
}

// ========== 主程序 ==========
Future<void> main() async {
  print('\n============================================');
  print('🔍 第一性原理：Hook 放行 / 吞 全链路审计测试');
  print('============================================\n');

  // -----------------------------------------------------------------------
  // 🔴 第一性原理公理 1：左键/右键/未知按键 → 必须 100% 放行，无论任何配置！
  // -----------------------------------------------------------------------
  print('【公理1】左键/右键/未知按键 → 必须永远放行（return false）');
  {
    final s = MockState();
    final press = buildPress(s);
    final router = buildRouter(s, press);
    // 模拟各种其他按键（_identifyButtonEvent 理论不会传来，但必须防御性放行）
    check('left  DOWN → 放行', router.handle('left', true) == false);
    check('left  UP   → 放行', router.handle('left', false) == false);
    check('right DOWN → 放行', router.handle('right', true) == false);
    check('right UP   → 放行', router.handle('right', false) == false);
    check('wheel DOWN → 放行', router.handle('wheel', true) == false);
    check('x1 but settings.button=middle → 放行（不是目标键）',
        router.handle('x1', true) == false);
    check('x3 but settings.button=middle → 放行（不是目标键）',
        router.handle('x3', true) == false);
    check('actions 列表为空（没触发任何动作）', s.actions.isEmpty);
    check('pressKinds 为空（没触发语音/翻页）', s.pressKinds.isEmpty);
  }
  print('');

  // -----------------------------------------------------------------------
  // 🔴 第一性原理公理 2：settings.enabled=false → 必须放行，不触发
  // -----------------------------------------------------------------------
  print('【公理2】未启用（enabled=false）→ 永远放行，不触发任何动作');
  {
    final s = MockState()..settings['enabled'] = false;
    final press = buildPress(s);
    final router = buildRouter(s, press);
    check('目标键 middle DOWN → 放行', router.handle('middle', true) == false);
    check('目标键 middle UP   → 放行', router.handle('middle', false) == false);
    check('actions 列表为空', s.actions.isEmpty);
    check('pressKinds 为空', s.pressKinds.isEmpty);
  }
  print('');

  // -----------------------------------------------------------------------
  // 🔴 第一性原理公理 3：safety 不是 safe / 过期 → 必须放行！
  // -----------------------------------------------------------------------
  print('【公理3】安全状态异常 → 永远放行（避免"卡鼠标"）');
  {
    final s = MockState()..safety = SafetyState.unsafeUnknown;
    final press = buildPress(s);
    final router = buildRouter(s, press);
    check('safety=unsafeUnknown → middle DOWN 放行', router.handle('middle', true) == false);
    s.safety = SafetyState.safeDesktopText;
    // 模拟 safety 过期：ts 是 10 秒前（ttl=1s）
    s.safetyTs = monotonicSeconds() - 10.0;
    check('safety 过期 10s → middle DOWN 放行', router.handle('middle', true) == false);
  }
  print('');

  // -----------------------------------------------------------------------
  // 🔴 第一性原理公理 4：capture（自动识别）模式 → 只吞目标 down+up，其他全部放行
  // -----------------------------------------------------------------------
  print('【公理4】自动识别 capture 模式 → 只吞第一个 down/up，其他放行');
  {
    final s = MockState()..settings['enabled'] = false; // capture 模式应该独立于 enabled
    final press = buildPress(s);
    final router = buildRouter(s, press);
    router.beginCapture();
    // 先按左键 → 必须放行（不是目标键集合）
    check('capture 中按 left DOWN → 放行', router.handle('left', true) == false);
    // 按中键 down → 吞掉并触发 capture 事件
    check('capture 中按 middle DOWN → 吞掉', router.handle('middle', true) == true);
    check('capture 触发事件 = middle', s.captured == 'middle');
    // middle up → 也吞掉（完成一次完整点击）
    check('capture 中按 middle UP → 吞掉', router.handle('middle', false) == true);
    // 后续 middle down → 不再是capture模式了 → 由于enabled=false → 放行
    check('capture 结束后 middle DOWN → 放行（enabled=false）',
        router.handle('middle', true) == false);
  }
  print('');

  // -----------------------------------------------------------------------
  // 🟢 功能场景1：单击目标键（tap_double 默认模式）→ 吞掉 + 300ms后触发语音
  // -----------------------------------------------------------------------
  print('【场景1】正常单击 middle：吞掉 down/up，300ms 后触发 send_shortcut');
  {
    final s = MockState()
      ..settings = {'enabled': true, 'button': 'middle', 'mode': 'tap_double'}
      ..safety = SafetyState.safeDesktopText
      ..safetyTs = monotonicSeconds();
    final press = buildPress(s)..configure('tap_double', doubleClickWindow: 0.05); // 用50ms快速窗口，测试不用等
    final router = buildRouter(s, press);
    check('DOWN middle → 吞', router.handle('middle', true) == true);
    check('actions 收了 down', s.actions.length == 1 && s.actions.last == ('middle', true));
    check('UP   middle → 吞', router.handle('middle', false) == true);
    check('actions 收了 up', s.actions.length == 2 && s.actions.last == ('middle', false));
    // 刚按完 0ms，窗口 50ms → 还没 fire
    check('50ms 窗口内 pressKinds 还空着（等窗口）', s.pressKinds.isEmpty);
    // 等 100ms 让 Timer 触发
    await Future.delayed(const Duration(milliseconds: 120));
    check('120ms 后触发 1 次语音', s.pressKinds.length == 1 &&
        s.pressKinds.last == triggerSendShortcut);
  }
  print('');

  // -----------------------------------------------------------------------
  // 🟢 功能场景2：快速双击目标键 → 吞 down1/up1/down2/up2，up2 后触发 replayClick（翻页）
  // -----------------------------------------------------------------------
  print('【场景2】快速双击：up2 触发 replayClick（翻页），之后单击=关闭翻页，3s后再单击=开语音');
  {
    final s = MockState()
      ..settings = {'enabled': true, 'button': 'middle', 'mode': 'tap_double'}
      ..safety = SafetyState.safeDesktopText
      ..safetyTs = monotonicSeconds();
    final press = buildPress(s)..configure('tap_double', doubleClickWindow: 0.2); // 200ms 窗口
    final router = buildRouter(s, press);
    // 第一次 down-up，间隔 30ms（<200ms）
    check('down1 吞', router.handle('middle', true) == true);
    await Future.delayed(const Duration(milliseconds: 30));
    check('up1   吞', router.handle('middle', false) == true);
    // 30ms 内 down2 → 双击判定
    await Future.delayed(const Duration(milliseconds: 30));
    check('down2 吞', router.handle('middle', true) == true);
    await Future.delayed(const Duration(milliseconds: 30));
    check('up2   吞', router.handle('middle', false) == true);
    // up2 之后立刻 fire replayClick（开翻页），不需要等窗口
    check('up2 之后立刻 fire=replayClick（开翻页）',
        s.pressKinds.isNotEmpty && s.pressKinds.last == triggerReplayClick);
    final kindsCountAfterDouble = s.pressKinds.length;

    // --- 翻页闭环验证：3 秒内单击 = 关闭翻页（也是 replayClick）---
    await Future.delayed(const Duration(milliseconds: 200)); // 确保还在 3s 内
    s.safetyTs = monotonicSeconds(); // 刷新 safety 避免过期
    check('3s 内 单击 middle down → 吞', router.handle('middle', true) == true);
    await Future.delayed(const Duration(milliseconds: 20));
    check('3s 内 单击 middle up → 吞', router.handle('middle', false) == true);
    // 等窗口 250ms 让单击判定出来
    await Future.delayed(const Duration(milliseconds: 260));
    // 这一次应该是 replayClick（关闭），不是 send_shortcut！
    check('这次 fire 仍然是 replayClick（关闭滚动），不是语音',
        s.pressKinds.length == kindsCountAfterDouble + 1 &&
            s.pressKinds.last == triggerReplayClick);

    // --- 3 秒过期后再单击 → 恢复语音 ---
    print('  ⏳ 等 3.1 秒让 rolling pending 过期…（验证过期后恢复开语音）');
    await Future.delayed(const Duration(milliseconds: 3200));
    s.safetyTs = monotonicSeconds();
    final before = s.pressKinds.length;
    router.handle('middle', true);
    await Future.delayed(const Duration(milliseconds: 20));
    router.handle('middle', false);
    await Future.delayed(const Duration(milliseconds: 260));
    check('3s 过期后单击 → fire=sendShortcut（恢复语音）',
        s.pressKinds.length == before + 1 && s.pressKinds.last == triggerSendShortcut);
  }
  print('');

  // -----------------------------------------------------------------------
  // 🟢 功能场景3：replace 模式 → 按下立刻触发语音（不等待双击窗口）
  // -----------------------------------------------------------------------
  print('【场景3】replace 模式：按下立刻触发，不等待窗口');
  {
    final s = MockState()
      ..settings = {'enabled': true, 'button': 'x1', 'mode': 'replace'}
      ..safety = SafetyState.safeDesktopText
      ..safetyTs = monotonicSeconds();
    final press = buildPress(s)..configure('replace');
    final router = buildRouter(s, press);
    check('目标键 x1 DOWN → 吞，立刻触发 sendShortcut', () {
      final swallow = router.handle('x1', true);
      return swallow == true &&
          s.pressKinds.length == 1 &&
          s.pressKinds.last == triggerSendShortcut;
    }());
    check('UP → 吞', router.handle('x1', false) == true);
  }
  print('');

  // -----------------------------------------------------------------------
  // 🟢 压力测试：1000 次随机"左键/右键/滚轮/中键"混合事件，中键=目标，
  //             必须：只有中键被吞，其他 100% 放行，零误伤
  // -----------------------------------------------------------------------
  print('【压力测试】1000 次混合事件（左键/右键/滚轮/中键各250次）→ 左键/右键/滚轮零误伤');
  {
    final s = MockState()
      ..settings = {'enabled': true, 'button': 'middle', 'mode': 'replace'}
      ..safety = SafetyState.safeDesktopText
      ..safetyTs = monotonicSeconds();
    final press = buildPress(s)..configure('replace');
    final router = buildRouter(s, press);

    int swallowLeft = 0, swallowRight = 0, swallowWheel = 0, swallowMiddle = 0;
    int releaseLeft = 0, releaseRight = 0, releaseWheel = 0, releaseMiddle = 0;
    final events = [
      for (int i = 0; i < 250; i++) ...[
        ('left', true),
        ('left', false),
        ('right', true),
        ('right', false),
        ('wheel', true),
        ('wheel', false),
        ('middle', true),
        ('middle', false),
      ]
    ]..shuffle();
    for (final (b, d) in events) {
      s.safetyTs = monotonicSeconds(); // 每次都刷新 safety，避免过期影响结果
      final sw = router.handle(b, d);
      if (b == 'left') {
        (sw ? swallowLeft++ : releaseLeft++);
      } else if (b == 'right') {
        (sw ? swallowRight++ : releaseRight++);
      } else if (b == 'wheel') {
        (sw ? swallowWheel++ : releaseWheel++);
      } else {
        (sw ? swallowMiddle++ : releaseMiddle++);
      }
    }
    check('左键 500 次：0 次被吞（放行 $releaseLeft/500）', swallowLeft == 0);
    check('右键 500 次：0 次被吞（放行 $releaseRight/500）', swallowRight == 0);
    check('滚轮 500 次：0 次被吞（放行 $releaseWheel/500）', swallowWheel == 0);
    check('中键 500 次：100% 被吞（吞 $swallowMiddle/500）', swallowMiddle == 500);
  }
  print('');

  // ========== 总结 ==========
  print('============================================');
  print('  审计结果：通过 $_pass / 总 ${_pass + _fail}');
  if (_fail == 0) {
    print('  🎉 100% 全绿！可以部署上线！');
  } else {
    print('  ❌ 有 $_fail 个失败，不许上线，先修！');
  }
  print('============================================\n');
  if (_fail > 0) throw Exception('有 $_fail 个审计失败，禁止上线');
}
