import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(Myapp());
}

class Myapp extends StatelessWidget {
  const Myapp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "sürüş analiz sistemi",
      home: Anasayfa(),
    );
  }
}

class Anasayfa extends StatefulWidget {
  const Anasayfa({super.key});

  @override
  State<Anasayfa> createState() => _AnasayfaState();
}

class _AnasayfaState extends State<Anasayfa> {
  double hiz = 0, ivme = 0, skor = 100, gx = 0, gy = 0, gz = 0;
  String uyari = "Surus Stabil";
  String obdDurumu = "OBD Bagli Degil";
  String apiDurumu = "";
  double hizLimiti = 50;
  double rpm = 0;
  double motorSicakligi = 0;
  DateTime? surusBaslangic;
  TextEditingController limitController = TextEditingController();
  double maxHiz = 0;

  double toplamHiz = 0;

  int hizOrnekSayisi = 0;
  List<FlSpot> grafikNoktalari = [];
  List<double> hizgecmisi = [];
  List<double> ivmegecmisi = [];
  List<double> frengecmisi = [];
  List<double> gazgecmisi = [];
  Random rnd = Random();
  BluetoothConnection? connection;
  BluetoothConnection? obdConnection;

  Future<void> izinleriAl() async {
    await Permission.bluetooth.request();

    await Permission.bluetoothConnect.request();

    await Permission.bluetoothScan.request();

    await Permission.location.request();
  }

  Future<void> bluetoothBaglan() async {
    List<BluetoothDevice> cihazlar = await FlutterBluetoothSerial.instance
        .getBondedDevices();

    BluetoothDevice esp32 = cihazlar.firstWhere(
      (d) => d.name == "ESP32_TELEMETRY",
    );

    connection = await BluetoothConnection.toAddress(esp32.address);

    connection!.input!.listen((data) {
      String gelen = ascii.decode(data);

      print(gelen);

      List<String> satirlar = gelen.split("\n");

      for (String satir in satirlar) {
        satir = satir.trim();

        if (satir.contains(",")) {
          List<String> parca = satir.split(",");

          if (parca.length >= 3) {
            double yenigx = double.tryParse(parca[0]) ?? 0;
            double yenigy = double.tryParse(parca[1]) ?? 0;
            double yeniGz = double.tryParse(parca[2]) ?? 0;
            setState(() {
              double filter(double eski, double yeni) {
                if ((yeni - eski).abs() < 0.02) {
                  return eski;
                }

                return (eski * 0.60) + (yeni * 0.40);
              }

              gx = filter(gx, yenigx);

              gy = filter(gy, yenigy);

              gz = filter(gz, yeniGz);
              ivme = filter(gy, yenigy);
            });
          }
        }
      }
    });
  }

  Future<void> obdBaglan() async {
    try {
      List<BluetoothDevice> cihazlar = await FlutterBluetoothSerial.instance
          .getBondedDevices();

      BluetoothDevice obd = cihazlar.firstWhere((d) => d.name == "OBDII");

      obdConnection = await BluetoothConnection.toAddress(obd.address);

      obdConnection!.input!.listen((data) {
        String cevap = ascii.decode(data);

        // HIZ (010D)
        if (cevap.contains("41 0D")) {
          List<String> parca = cevap.trim().split(" ");

          if (parca.length >= 3) {
            int hizObd = int.parse(parca[2], radix: 16);

            setState(() {
              hiz = hizObd.toDouble();
            });
          }
        }

        // SICAKLIK (0105)
        if (cevap.contains("41 05")) {
          List<String> parca = cevap.trim().split(" ");

          if (parca.length >= 3) {
            int sicaklik = int.parse(parca[2], radix: 16) - 40;

            setState(() {
              motorSicakligi = sicaklik.toDouble();
            });
          }
        }

        // RPM (010C)
        if (cevap.contains("41 0C")) {
          List<String> parca = cevap.trim().split(" ");

          if (parca.length >= 4) {
            int A = int.parse(parca[2], radix: 16);

            int B = int.parse(parca[3], radix: 16);

            double rpmDegeri = ((A * 256) + B) / 4;

            setState(() {
              rpm = rpmDegeri;
            });
          }
        }
      });

      setState(() {
        obdDurumu = "OBD Baglandi";
        obdConnection!.output.add(Uint8List.fromList(ascii.encode("ATZ\r")));

        Future.delayed(Duration(seconds: 1), () {
          obdConnection!.output.add(Uint8List.fromList(ascii.encode("ATE0\r")));
        });

        Future.delayed(Duration(seconds: 2), () {
          obdConnection!.output.add(
            Uint8List.fromList(ascii.encode("ATSP6\r")),
          );
        });
      });
    } catch (e) {
      setState(() {
        obdDurumu = "OBD Bulunamadi: $e";
      });
    }
  }

  void gpsBaslat() {
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,

        distanceFilter: 0,
      ),
    ).listen((Position pos) {
      setState(() {
        double yenihiz = pos.speed * 3.6;

        if (yenihiz < 3) {
          yenihiz = 0;
        }

        hiz = yenihiz;
      });
    });
  }

  Future<void> hizLimitiGetir() async {
    Position pos = await Geolocator.getCurrentPosition();

    double lat = pos.latitude;

    double lon = pos.longitude;

    var response = await http.post(
      Uri.parse("https://overpass-api.de/api/interpreter"),
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: {
        "data":
            """
[out:json];
way(around:100,$lat,$lon)["maxspeed"];
out tags;
""",
      },
    );
    print("STATUS:");
    print(response.statusCode);
    setState(() {
      apiDurumu = "Kod: ${response.statusCode}\n${response.body}";
    });
    print("BODY:");
    print(response.body);
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);

      if (data["elements"].length > 0) {
        String limit = data["elements"][0]["tags"]["maxspeed"];

        double? yeniLimit = double.tryParse(
          limit.replaceAll(RegExp(r'[^0-9]'), ''),
        );

        if (yeniLimit != null) {
          setState(() {
            hizLimiti = yeniLimit;
          });
        }
      }
    }
  }

  List<TelemetriVeri> gecmisVeriler = [];
  Future<void> veriKaydet() async {
    await FirebaseFirestore.instance.collection("telemetri").add({
      "hiz": hiz,
      "ivme": ivme,

      "skor": skor,

      "zaman": DateTime.now(),
    });
  }

  Future<void> surusuBitir() async {
    DateTime bitis = DateTime.now();
    Duration surusSuresi = bitis.difference(surusBaslangic!);

    double ortalamaHiz = hizOrnekSayisi == 0 ? 0 : toplamHiz / hizOrnekSayisi;

    await FirebaseFirestore.instance.collection("surusler").add({
      "baslangıç": surusBaslangic,
      "surusSuresi": surusSuresi.inSeconds,
      "bitiş": bitis,

      "ortalamaHiz": ortalamaHiz,

      "maxHiz": maxHiz,

      "ortalamaSkor": skor,
    });
    surusBaslangic = DateTime.now();

    maxHiz = 0;

    toplamHiz = 0;

    hizOrnekSayisi = 0;
    skor = 100;

    uyari = "Surus Stabil";
  }

  void fonk1() {
    setState(() {
      hizgecmisi.add(hiz);
      if (hizgecmisi.length > 20) {
        hizgecmisi.removeAt(0);
      }
      if (hiz > maxHiz) {
        maxHiz = hiz;
      }

      toplamHiz += hiz;

      hizOrnekSayisi++;
      print(ivme);
      ivmegecmisi.add(ivme);

      if (ivmegecmisi.length > 20) {
        ivmegecmisi.removeAt(0);
      }

      if (gy.abs() > 0.32) {
        skor -= 5;
      }

      if (gx.abs() > 0.70) {
        skor -= 20;
      }

      if (hiz > 140) {
        skor -= 15;
      }

      if (gy.abs() > 0.60) {
        skor -= 20;
      }

      if (gx.abs() > 1.00) {
        skor -= 35;
      }

      if (skor < 0) {
        skor = 0;
      }
      if (hiz > hizLimiti) {
        uyari = "HIZ LIMITI ASILDI!";
      } else if (gy.abs() > 0.15) {
        uyari = "Sert Fren / Hizlanma!";
      } else if (gx.abs() > 0.60) {
        uyari = "Agresif Donus!";
      } else if (hiz > 140) {
        uyari = "Yuksek Hiz!";
      } else {
        uyari = "Surus Stabil";
      }

      gecmisVeriler.add(TelemetriVeri(hiz: hiz, ivme: ivme, skor: skor));
    });
    veriKaydet();
  }

  @override
  void initState() {
    super.initState();
    izinleriAl();
    // gpsBaslat();
    hizLimitiGetir();
    bluetoothBaglan();
    obdBaglan();

    surusBaslangic = DateTime.now();
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (obdConnection != null) {
        obdConnection!.output.add(Uint8List.fromList(ascii.encode("010D\r")));

        Future.delayed(Duration(milliseconds: 250), () {
          obdConnection!.output.add(Uint8List.fromList(ascii.encode("010C\r")));
        });

        Future.delayed(Duration(milliseconds: 500), () {
          obdConnection!.output.add(Uint8List.fromList(ascii.encode("0105\r")));
        });
      }
    });
    Timer.periodic(Duration(seconds: 20), (timer) {
      hizLimitiGetir();
    });

    Timer.periodic(Duration(milliseconds: 800), (timer) {
      fonk1();
    });
    Timer.periodic(Duration(minutes: 5), (timer) {
      surusuBitir();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("sürüş analiz sistemi v1 ")),
      body: ListView(
        children: [
          Card(
            margin: EdgeInsets.all(8),

            child: Padding(
              padding: EdgeInsets.all(20),

              child: Column(
                children: [
                  Container(
                    width: 220,

                    height: 220,

                    decoration: BoxDecoration(
                      shape: BoxShape.circle,

                      color: Colors.black,

                      boxShadow: [
                        BoxShadow(
                          blurRadius: 20,

                          color: Colors.blue.withOpacity(0.4),
                        ),
                      ],
                    ),

                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,

                      children: [
                        Text(
                          hiz.toStringAsFixed(0),

                          style: TextStyle(
                            fontSize: 70,

                            color: Colors.white,

                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        Text(
                          "km/h",

                          style: TextStyle(fontSize: 24, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "Motor Sicakligi: ${motorSicakligi.toStringAsFixed(0)} °C",
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "RPM: ${rpm.toStringAsFixed(0)}",
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
          SizedBox(height: 15),

          Text(
            "Yol Limiti: ${hizLimiti.toStringAsFixed(0)} km/h",

            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),

          Text(
            obdDurumu,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(8),

                    child: Column(
                      children: [Text("Lat G"), Text(gx.toStringAsFixed(2))],
                    ),
                  ),
                ),
              ),

              Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(8),

                    child: Column(
                      children: [Text("Long G"), Text(gy.toStringAsFixed(2))],
                    ),
                  ),
                ),
              ),

              Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(8),

                    child: Column(
                      children: [Text("Vert G"), Text(gz.toStringAsFixed(2))],
                    ),
                  ),
                ),
              ),
            ],
          ),

          Card(
            color: skor > 80
                ? Colors.green
                : skor > 50
                ? Colors.orange
                : Colors.red,

            child: Padding(
              padding: EdgeInsets.all(20),

              child: Column(
                children: [
                  Text(
                    "Guvenli Surus Skoru",

                    style: TextStyle(fontSize: 20, color: Colors.white),
                  ),

                  SizedBox(height: 10),

                  Text(
                    skor.toStringAsFixed(0),

                    style: TextStyle(
                      fontSize: 50,

                      fontWeight: FontWeight.bold,

                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            color: uyari == "Surus Stabil" ? Colors.green : Colors.red,

            child: Padding(
              padding: EdgeInsets.all(20),

              child: Center(
                child: Text(
                  uyari,

                  style: TextStyle(
                    fontSize: 28,

                    color: Colors.white,

                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await surusuBitir();

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("Surus Kaydedildi")));
                },
                child: Text("SURUSU BITIR VE KAYDET"),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: limitController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: "Hiz Limiti"),
                  ),

                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        hizLimiti = double.tryParse(limitController.text) ?? 50;
                      });
                    },
                    child: Text("Limiti Ayarla"),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SuruslerEkrani()),
                  );
                },
                child: Text("SON SURUSLER"),
              ),
            ),
          ),
          ExpansionTile(
            title: Text("obd test ekranı"),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("ATZ\r")),
                      );
                    },
                    child: Text("ATZ"),
                  ),

                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("ATE0\r")),
                      );
                    },
                    child: Text("ATE0"),
                  ),

                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("ATSP6\r")),
                      );
                    },
                    child: Text("ATSP6"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("010C\r")),
                      );
                    },
                    child: Text("010C"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("0105\r")),
                      );
                    },
                    child: Text("0105"),
                  ),

                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("0100\r")),
                      );
                    },
                    child: Text("0100"),
                  ),

                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("010D\r")),
                      );
                    },
                    child: Text("010D"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("ATDP\r")),
                      );
                    },
                    child: Text("ATDP"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      obdConnection!.output.add(
                        Uint8List.fromList(ascii.encode("ATAT1\r")),
                      );
                    },
                    child: Text("atat1"),
                  ),
                ],
              ),
            ],
          ),
          Card(
            margin: EdgeInsets.all(8),

            child: Column(
              children: [
                Text(
                  "Geçmiş Veriler",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                ...gecmisVeriler.reversed
                    .take(5)
                    .map((veri) => Text("${veri.hiz.toStringAsFixed(0)} km/h")),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AnalizEkrani(
                          hizGecmisi: hizgecmisi,
                          ivmeGecmisi: ivmegecmisi,
                        ),
                      ),
                    );
                  },
                  child: Text("analiz ekranı "),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TelemetriVeri {
  double hiz;
  double ivme;

  double skor;

  TelemetriVeri({required this.hiz, required this.ivme, required this.skor});
}

class AnalizEkrani extends StatelessWidget {
  final List<double> hizGecmisi;
  final List<double> ivmeGecmisi;

  const AnalizEkrani({
    super.key,
    required this.hizGecmisi,
    required this.ivmeGecmisi,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Analiz")),

      body: ListView(
        children: [
          Text("hız"),
          SizedBox(
            height: 250,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        hizGecmisi.length,
                        (index) => FlSpot(index.toDouble(), hizGecmisi[index]),
                      ),
                      isCurved: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text("ivme"),
          SizedBox(
            height: 250,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        ivmeGecmisi.length,
                        (index) => FlSpot(index.toDouble(), ivmeGecmisi[index]),
                      ),
                      isCurved: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SuruslerEkrani extends StatelessWidget {
  const SuruslerEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Son Surusler")),

      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection("surusler")
            .orderBy("bitiş", descending: true)
            .snapshots(),

        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          var belgeler = snapshot.data!.docs;

          return ListView.builder(
            itemCount: belgeler.length,

            itemBuilder: (context, index) {
              var veri = belgeler[index];

              return Card(
                margin: EdgeInsets.all(8),

                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 8),

                      Text(
                        "Ortalama Hiz: ${veri["ortalamaHiz"].toStringAsFixed(0)} km/h",
                      ),
                      Text(
                        "Maksimum Hiz: ${veri["maxHiz"].toStringAsFixed(0)} km/h",
                      ),
                      Text("Skor: ${veri["ortalamaSkor"].toStringAsFixed(0)}"),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
