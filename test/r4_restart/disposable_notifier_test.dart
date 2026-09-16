import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/test/state/disposable_notifier.dart';

class _N extends DisposableNotifier {
  void poke() => notifyListeners();
}

void main() {
  test('notifyListeners after dispose is a no-op instead of throwing', () {
    final n = _N();
    var calls = 0;
    n.addListener(() => calls++);
    n.poke();
    expect(calls, 1);
    n.dispose();
    expect(n.isDisposed, isTrue);
    expect(n.poke, returnsNormally); // late async completion after pop
    expect(calls, 1);
  });
}
