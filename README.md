
# OBD Entegreli Sürüş Analiz Uygulaması

Flutter ile geliştirilmiş, OBD-II cihazı üzerinden araç verilerini okuyup sürüş davranışını analiz eden mobil uygulama.

## Özellikler
- OBD-II üzerinden anlık hız, RPM ve motor sıcaklığı okuma
- Bluetooth ile ESP32 üzerinden ivme (G) verisi alma
- GPS ile konum ve hız takibi
- OpenStreetMap API ile yol hız limiti sorgulama
- Firebase Firestore ile sürüş verilerini kaydetme
- Güvenli sürüş skoru hesaplama ve uyarı sistemi
- fl_chart ile hız ve ivme grafikleri

## Kullanılan Teknolojiler
- Flutter / Dart
- Firebase (Firestore)
- Bluetooth Serial
- OBD-II (ELM327)
- GPS (Geolocator)
- Overpass API (Hız limiti)
- fl_chart (Grafikler)

## Not
Bu proje, Flutter ile geliştirdiğim ilk uygulamadır. Sıfırdan Flutter öğrenme süreci dahil iki ayda tamamlanmıştır.

## Video
[Proje tanıtım videosu](https://youtu.be/Z-AhLTd7pWE)
