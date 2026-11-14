# Vetőgép V2 az ESP32S3 RCv1.7 panelen (második, kisebb tudású panel)

Az AgOpenGPS Rate Controller panel (Vági F. / Gunics B., ESP32-S3-WROOM-1U, 16 MB flash, **PSRAM nincs**)
ugyanazt a vetőgép-firmware-t futtatja, mint a Waveshare panel – a VT, a web, a Windows-program, az
AgOpenGPS, a Keya CAN-motor és a **külső kijelző** (CAN, Proprietary A) ugyanúgy működik.
A panel adott lábkészlete miatt kevesebbet tud:

| Van | Nincs |
|---|---|
| 2 adagolómotor enkóderrel (a panel motorvezérlője, PWM + DIR), vagy Keya CAN-motor | HX711 mérleg (leforgatási mérlegelés kézzel) |
| 2 tartályszenzor, munkakapcsoló | DS18B20 hőmérők (olajhűtés) |
| kerékjeladó, turbina-jeladó, leforgató gomb (szabad lábakon, illesztéssel) | hangjelző |
| 8 kimenet a PCA9685-ön (kuplungok, terelőszelep, 2 munkalámpa, tartalék) | |
| nyomásmérés (ADS1115 a panelen), Ethernet (W5500) | |

Kiadási fájlok: `VETOGEP_RCV17_16MB_vXXX_FULL_0x0.bin` (USB) és `VETOGEP_RCV17_16MB_vXXX_OTA.bin` (OTA).
**A Waveshare fájlját ne töltsd erre a panelre, és fordítva** – más lábak, más CAN-láb.

## Első feltöltés előtt: VDD_SPI eFuse (minden új panelen!)

A GPIO45 strapping láb a W5500 INT-re kötött. Hogy a W5500 induláskor ne kapcsolja 1,8 V-ra a flash-t,
a flash feszültségét eFuse-zal 3,3 V-ra kell rögzíteni (egyszeri, visszafordíthatatlan):

```
espefuse.py --port COMx set_flash_voltage 3.3V
```

Ha a permetező firmware már futott a panelen, ez már megtörtént.

## Lábkiosztás

A motoros bemenetek a Rate Controller programbeli modulbeállítás szerint (Sensor 1 / 2: Flow, Dir, PWM, Bin).

| Jel | Láb | Megjegyzés |
|---|---|---|
| ISOBUS CAN TX / RX | GPIO17 / GPIO16 | MCP2562, 120 Ω lezárás jumperrel; a Keya motorok és a külső kijelző is ezen |
| 1. adagoló enkóder (Flow 1) | GPIO21 | belső felhúzás |
| 2. adagoló enkóder (Flow 2) | GPIO47 | belső felhúzás |
| 1. motor PWM / DIR | GPIO5 / GPIO4 | a panel motorvezérlője |
| 2. motor PWM / DIR | GPIO15 / GPIO7 | a panel motorvezérlője |
| Motorvezérlő engedélyezés | GPIO13 | elektromos (PWM) hajtásnál magas, egyébként alacsony |
| Munkakapcsoló (Work) | GPIO40 | NO / NC beállítás |
| 1. / 2. tartály (Bin 1 / 2) | GPIO41 / GPIO42 | NO / NC beállítás |
| Kerékjeladó | GPIO1 (szabad) | **3,3 V-os láb – optocsatoló vagy feszültségosztó kell** |
| Turbina-jeladó | GPIO2 (szabad) | **3,3 V-os láb – optocsatoló vagy feszültségosztó kell** |
| Leforgató nyomógomb | GPIO3 (szabad) | GND-re záró gomb; bekapcsoláskor 3 s nyomva: WiFi szerviz mód |
| Kimenet 1 / 2 | PCA9685 csatorna 0 / 2 | 1. / 2. adagoló kuplung |
| Kimenet 3 | csatorna 4 | terelőszelep (nyitás / nyomjelző) |
| Kimenet 4 / 5 | csatorna 6 / 8 | 1. / 2. munkalámpa (Beállítások → Kiegészítők: a kimenet állítható) |
| Kimenet 6–8 | csatorna 10 / 12 / 14 | tartalék |
| Nyomás | ADS1115 A0 | 0–5 V |
| Ethernet W5500 | MISO37 MOSI35 SCLK36 CS38 INT45 RST48 | AgOpenGPS, web, Windows-program |

A PCA9685 kimenetek H-hidak (kimenetenként két csatorna, az eredeti RC firmware kiosztása): bekapcsolt
kimenetnél a páros csatorna magas, a páratlan alacsony; kikapcsoltnál mindkettő alacsony. A beállításokban a
„Relé n” megnevezés ezen a panelen a „Kimenet n”-t jelenti (a számozás a Waveshare reléivel azonos).

A szabad lábak (GPIO1–3) közvetlenül az ESP32-re mennek: 12 V-os jeladót **csak illesztéssel** (pl. PC817
optocsatoló, vagy osztó + Zener) szabad rákötni. A jel aktív alacsony (GND-re húz), belső felhúzással.

## Beállítás

* Beállítások → Hajtás, motor → Hajtás: **Elektr. PWM**, Motorvezérlő: **PWM + DIR** (a panel saját vezérlője).
  „Csak PWM” módban is a DIR láb alacsony kimenet marad (nem lebeg).
* A Rate Controller programban bepipált **Invert** a forgásirányt fordítja: itt Motorszabályzás →
  **Forgásirány megfordítása**.
* Keya CAN-motorral: Hajtás = **Elektr. Keya**; a motorok a 17/16-os CAN-en, a többi ugyanaz, mint a Waveshare-en.
* Olajhűtés, mérleg ezen a panelen nem használható (nincs hőmérő- és mérlegbemenet) – maradjanak kikapcsolva.
