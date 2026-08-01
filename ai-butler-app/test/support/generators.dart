import 'dart:math';

const List<int> propertySeeds = <int>[1, 7, 42, 1337, 20260801];
const int casesPerSeed = 40;

void forEachSeed(void Function(Random random, int seed) body) {
  for (final seed in propertySeeds) {
    body(Random(seed), seed);
  }
}

class Gen {
  Gen(this.random);
  final Random random;

  int intInRange(int min, int max) => max <= min ? min : min + random.nextInt(max - min + 1);
  bool boolean([double p = 0.5]) => random.nextDouble() < p;
  T oneOf<T>(List<T> options) => options[random.nextInt(options.length)];

  String text({int minLen = 0, int maxLen = 20}) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789 王測試@.-_';
    final length = intInRange(minLen, maxLen);
    return String.fromCharCodes(List.generate(length, (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length))));
  }

  String mobile() => '09${List.generate(8, (_) => random.nextInt(10)).join()}';

  String email() {
    final local = text(minLen: 1, maxLen: 8).replaceAll(RegExp(r'[@\s.]'), 'x');
    return '$local@example.com';
  }

  String twoDigitCode() => intInRange(0, 99).toString().padLeft(2, '0');
}
