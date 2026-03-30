// lib/core/utils.dart



class AppUtils {
  // Eşleşme kodu için kullanılan alfabe (Home'dan buraya aldık)
  static const String pairCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  // Eşleşme kodu üreten fonksiyon
  static String generatePairCode(String locatorId) {
    int hash = 17;
    for (final unit in locatorId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }

    const base = pairCodeAlphabet;
    final buffer = StringBuffer();
    int value = hash;

    for (int i = 0; i < 6; i++) {
      buffer.write(base[value % base.length]);
      value = value ~/ base.length;
    }

    return buffer.toString();
  }

  // Buraya ileride diğer statik yardımcı fonksiyonları (tarih formatlama, mesafe hesaplama vb.) ekleyebiliriz.
}