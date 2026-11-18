import 'dart:io';

String rupiah(int n) {
  final s = n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return 'Rp$s';
}

class DiningException implements Exception {
  final String pesan;
  DiningException(this.pesan);
  @override
  String toString() => pesan;
}

class SaldoTidakCukupException extends DiningException {
  SaldoTidakCukupException(int saldo, int biaya)
      : super('TIDAK BISA MAKAN! Saldo ${rupiah(saldo)}, '
            'biaya ${rupiah(biaya)}. Silakan ISI DEPOSITO lagi.');
}

class MahasiswaTidakDitemukanException extends DiningException {
  MahasiswaTidakDitemukanException(int id)
      : super('Kartu dengan ID $id tidak terdaftar.');
}

class NominalTidakValidException extends DiningException {
  NominalTidakValidException() : super('Nominal harus lebih dari 0.');
}

class OpsiMakanTidakValidException extends DiningException {
  OpsiMakanTidakValidException(String jenis)
      : super('Opsi makan "$jenis" tidak dikenal (pilih dine in / take away).');
}


abstract class Pengguna {
  final int _id; // private
  final String _nama; // private

  Pengguna(this._id, this._nama);

  int get id => _id;
  String get nama => _nama;
  String get peran; // diimplementasikan subclass

  @override
  String toString() => '[$peran] $_nama (ID: $_id)';
}

class Mahasiswa extends Pengguna {
  int _deposito; // private: hanya bisa diubah lewat method

  Mahasiswa(int id, String nama, {int depositoAwal = 0})
      : _deposito = depositoAwal,
        super(id, nama);

  @override
  String get peran => 'Mahasiswa';

  int get deposito => _deposito; // read-only dari luar

  bool bisaMakan(int biaya) => _deposito >= biaya;

  void isiDeposito(int nominal) {
    if (nominal <= 0) throw NominalTidakValidException();
    _deposito += nominal;
  }

  void potongDeposito(int biaya) {
    if (!bisaMakan(biaya)) throw SaldoTidakCukupException(_deposito, biaya);
    _deposito -= biaya;
  }
}


abstract class OpsiMakan {
  String get nama;
  int get biayaDasar => 15000;
  int hitungBiaya(); // perilaku berbeda tiap subclass
}

class DineIn extends OpsiMakan {
  @override
  String get nama => 'Dine In';

  @override
  int hitungBiaya() => biayaDasar;
}

class TakeAway extends OpsiMakan {
  static const int biayaKemasan = 2000;

  @override
  String get nama => 'Take Away';

  @override
  int hitungBiaya() => biayaDasar + biayaKemasan;
}

class OpsiMakanFactory {
  static OpsiMakan buat(String jenis) {
    switch (jenis.toLowerCase().trim()) {
      case 'dine in':
      case 'dinein':
        return DineIn();
      case 'take away':
      case 'takeaway':
        return TakeAway();
      default:
        throw OpsiMakanTidakValidException(jenis);
    }
  }
}

class RiwayatLog {
  static final RiwayatLog _instance = RiwayatLog._internal();
  factory RiwayatLog() => _instance;
  RiwayatLog._internal();

  final Map<int, List<String>> _catatanPerAkun = {};

  void catat(int idKartu, String pesan) {
    final t = DateTime.now().toString().substring(0, 19);
    _catatanPerAkun.putIfAbsent(idKartu, () => []).add('[$t] $pesan');
  }

  List<String> catatanUntuk(int idKartu) =>
      List.unmodifiable(_catatanPerAkun[idKartu] ?? <String>[]);
}

abstract class MahasiswaRepository {
  void simpan(Mahasiswa m);
  Mahasiswa cariById(int id);
  List<Mahasiswa> semua();
}

class MahasiswaRepositoryMemori implements MahasiswaRepository {
  final Map<int, Mahasiswa> _data = {};

  @override
  void simpan(Mahasiswa m) => _data[m.id] = m;

  @override
  Mahasiswa cariById(int id) {
    final m = _data[id];
    if (m == null) throw MahasiswaTidakDitemukanException(id);
    return m;
  }

  @override
  List<Mahasiswa> semua() => _data.values.toList();
}

abstract class MetodePembayaran {
  void bayar(Mahasiswa mhs, int jumlah);
}

class PembayaranDeposito implements MetodePembayaran {
  @override
  void bayar(Mahasiswa mhs, int jumlah) => mhs.potongDeposito(jumlah);
}

class DiningService {
  final MahasiswaRepository _repo;
  final MetodePembayaran _pembayaran;
  final RiwayatLog _log = RiwayatLog();

  DiningService(this._repo, this._pembayaran);

  String tapKartu(int idKartu, OpsiMakan opsi) {
    final mhs = _repo.cariById(idKartu);
    final biaya = opsi.hitungBiaya(); // polimorfisme
    try {
      _pembayaran.bayar(mhs, biaya);
    } on SaldoTidakCukupException {
      _log.catat(mhs.id, 'GAGAL  ${opsi.nama} - saldo kurang');
      rethrow;
    }
    _log.catat(mhs.id, 'SUKSES ${opsi.nama} -${rupiah(biaya)}');
    return 'OK  ${mhs.nama} makan ${opsi.nama}. '
        'Terpotong ${rupiah(biaya)} | Sisa deposito ${rupiah(mhs.deposito)}';
  }

  void isiDeposito(int idKartu, int nominal) {
    final mhs = _repo.cariById(idKartu);
    mhs.isiDeposito(nominal);
    _log.catat(mhs.id, 'TOPUP  +${rupiah(nominal)}');
  }

  List<String> riwayat(int idKartu) {
    final mhs = _repo.cariById(idKartu);
    return _log.catatanUntuk(mhs.id);
  }

  int cekSaldo(int idKartu) => _repo.cariById(idKartu).deposito;

  List<Mahasiswa> daftar() => _repo.semua();
}

void main() {
  final repo = MahasiswaRepositoryMemori();
  final service = DiningService(repo, PembayaranDeposito());

  // Data mahasiswa 
  repo.simpan(Mahasiswa(111, 'Rebecca', depositoAwal: 50000));
  repo.simpan(Mahasiswa(169, 'Jennifer', depositoAwal: 100000));
  repo.simpan(Mahasiswa(201, 'Rolas', depositoAwal: 30000));
  repo.simpan(Mahasiswa(399, 'Ferdi', depositoAwal: 16000));
  repo.simpan(Mahasiswa(104, 'Joana', depositoAwal: 10000));
  repo.simpan(Mahasiswa(428, 'Marcel', depositoAwal: 40000));

  
  print('=== SIMULASI: SEMUA MAHASISWA TAP KARTU ===');
  final ronde = ['dine in', 'take away'];
  for (final jenis in ronde) {
    print('\n--- Ronde: $jenis ---');
    for (final mhs in service.daftar()) {
      try {
        print(service.tapKartu(mhs.id, OpsiMakanFactory.buat(jenis)));
      } on SaldoTidakCukupException catch (e) {
        print('XX  ${mhs.nama}: $e');
      } on DiningException catch (e) {
        print('XX  ${mhs.nama}: $e');
      }
    }
  }

  
  print('\n=== MENU DINING ASRAMA UNAI ===');
  var jalan = true;
  while (jalan) {
    print('\n1. Makan (tap kartu)');
    print('2. Isi deposito');
    print('3. Cek saldo');
    print('4. Daftar mahasiswa');
    print('5. Riwayat transaksi');
    print('0. Keluar');
    stdout.write('Pilih menu: ');
    final pilihan = stdin.readLineSync()?.trim();

    try {
      switch (pilihan) {
        case '1':
          final id = _bacaInt('ID kartu mahasiswa: ');
          stdout.write('Pilih (dine in / take away): ');
          final jenis = stdin.readLineSync() ?? '';
          print(service.tapKartu(id, OpsiMakanFactory.buat(jenis)));
          break;
        case '2':
          final id = _bacaInt('ID kartu mahasiswa: ');
          final nominal = _bacaInt('Nominal isi ulang (Rp): ');
          service.isiDeposito(id, nominal);
          print('Deposito berhasil diisi. Saldo: '
              '${rupiah(service.cekSaldo(id))}');
          break;
        case '3':
          final id = _bacaInt('ID kartu mahasiswa: ');
          print('Saldo deposito: ${rupiah(service.cekSaldo(id))}');
          break;
        case '4':
          for (final m in service.daftar()) {
            final status = m.bisaMakan(15000) ? 'Aktif' : 'ISI ULANG!';
            print('$m | ${rupiah(m.deposito)} | $status');
          }
          break;
        case '5':
          final id = _bacaInt('ID kartu mahasiswa: ');
          final log = service.riwayat(id);
          if (log.isEmpty) print('Belum ada transaksi untuk akun ini.');
          for (final c in log) {
            print(c);
          }
          break;
        case '0':
          jalan = false;
          print('Terima kasih!');
          break;
        default:
          print('Menu tidak valid.');
      }
    } on SaldoTidakCukupException catch (e) {
      print('XX $e');
    } on DiningException catch (e) {
      print('Error: $e');
    } on FormatException {
      print('Error: input harus berupa angka.');
    } catch (e) {
      print('Terjadi kesalahan tak terduga: $e');
    }
  }
}

int _bacaInt(String label) {
  stdout.write(label);
  return int.parse(stdin.readLineSync()?.trim() ?? '');
}
