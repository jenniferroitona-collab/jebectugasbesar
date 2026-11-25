import 'dart:io';

import 'package:sqlite3/sqlite3.dart';


String rupiah(int n) {
  final s = n
      .abs()
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '${n < 0 ? '-' : ''}Rp$s';
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
  String get peran;

  @override
  String toString() => '[$peran] $_nama (ID: $_id)';
}

class Mahasiswa extends Pengguna {
  int _deposito; // private: hanya berubah lewat method

  Mahasiswa(int id, String nama, {int depositoAwal = 0})
      : _deposito = depositoAwal,
        super(id, nama);

  @override
  String get peran => 'Mahasiswa';

  int get deposito => _deposito;

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
  int hitungBiaya();
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

class Transaksi {
  final int idKartu;
  final String jenis; // MAKAN / GAGAL / TOPUP
  final String keterangan;
  final int nominal; // negatif = uang keluar, positif = isi ulang
  final String waktu;

  Transaksi(this.idKartu, this.jenis, this.keterangan, this.nominal, this.waktu);

  @override
  String toString() =>
      '[$waktu] ${jenis.padRight(5)} ${keterangan.padRight(22)} ${rupiah(nominal)}';
}


abstract class MahasiswaRepository {
  void tambahJikaBelum(Mahasiswa m);
  void perbarui(Mahasiswa m);
  Mahasiswa cariById(int id);
  List<Mahasiswa> semua();
}

abstract class RiwayatRepository {
  void catat(int idKartu, String jenis, String keterangan, int nominal);
  List<Transaksi> ambilPerAkun(int idKartu);
}

abstract class MetodePembayaran {
  void bayar(Mahasiswa mhs, int jumlah);
}

abstract class UnitOfWork {
  T jalankan<T>(T Function() aksi);
}

class PembayaranDeposito implements MetodePembayaran {
  @override
  void bayar(Mahasiswa mhs, int jumlah) => mhs.potongDeposito(jumlah);
}


class DatabaseHelper implements UnitOfWork {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static const String namaFile = 'jebegtug.dart';
  Database? _db;

  Database get db => _db ??= _buka();

  Database _buka() {
    final d = sqlite3.open(namaFile);
    d.execute('PRAGMA foreign_keys = ON;');
    d.execute('''
      CREATE TABLE IF NOT EXISTS mahasiswa (
        id INTEGER PRIMARY KEY,
        nama TEXT NOT NULL,
        deposito INTEGER NOT NULL CHECK (deposito >= 0)
      );
    ''');
    d.execute('''
      CREATE TABLE IF NOT EXISTS transaksi (
        no INTEGER PRIMARY KEY AUTOINCREMENT,
        id_kartu INTEGER NOT NULL,
        jenis TEXT NOT NULL,
        keterangan TEXT NOT NULL,
        nominal INTEGER NOT NULL,
        waktu TEXT NOT NULL,
        FOREIGN KEY (id_kartu) REFERENCES mahasiswa(id)
      );
    ''');
    return d;
  }

  
  @override
  T jalankan<T>(T Function() aksi) {
    db.execute('BEGIN');
    try {
      final hasil = aksi();
      db.execute('COMMIT');
      return hasil;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void resetData() {
    db.execute('DELETE FROM transaksi');
    db.execute('DELETE FROM mahasiswa');
  }

  void tutup() {
    _db?.dispose();
    _db = null;
  }
}

class SqliteMahasiswaRepository implements MahasiswaRepository {
  final DatabaseHelper _helper;
  SqliteMahasiswaRepository(this._helper);

  @override
  void tambahJikaBelum(Mahasiswa m) {
    _helper.db.execute(
      'INSERT OR IGNORE INTO mahasiswa (id, nama, deposito) VALUES (?, ?, ?)',
      [m.id, m.nama, m.deposito],
    );
  }

  @override
  void perbarui(Mahasiswa m) {
    _helper.db.execute(
      'UPDATE mahasiswa SET deposito = ? WHERE id = ?',
      [m.deposito, m.id],
    );
  }

  @override
  Mahasiswa cariById(int id) {
    final hasil = _helper.db
        .select('SELECT id, nama, deposito FROM mahasiswa WHERE id = ?', [id]);
    if (hasil.isEmpty) throw MahasiswaTidakDitemukanException(id);
    return _dariRow(hasil.first);
  }

  @override
  List<Mahasiswa> semua() {
    final hasil = _helper.db
        .select('SELECT id, nama, deposito FROM mahasiswa ORDER BY nama');
    return [for (final row in hasil) _dariRow(row)];
  }

  Mahasiswa _dariRow(Row row) => Mahasiswa(
        row['id'] as int,
        row['nama'] as String,
        depositoAwal: row['deposito'] as int,
      );
}

class SqliteRiwayatRepository implements RiwayatRepository {
  final DatabaseHelper _helper;
  SqliteRiwayatRepository(this._helper);

  @override
  void catat(int idKartu, String jenis, String keterangan, int nominal) {
    final waktu = DateTime.now().toString().substring(0, 19);
    _helper.db.execute(
      'INSERT INTO transaksi (id_kartu, jenis, keterangan, nominal, waktu) '
      'VALUES (?, ?, ?, ?, ?)',
      [idKartu, jenis, keterangan, nominal, waktu],
    );
  }

  
  @override
  List<Transaksi> ambilPerAkun(int idKartu) {
    final hasil = _helper.db.select(
      'SELECT id_kartu, jenis, keterangan, nominal, waktu FROM transaksi '
      'WHERE id_kartu = ? ORDER BY no',
      [idKartu],
    );
    return [
      for (final r in hasil)
        Transaksi(r['id_kartu'] as int, r['jenis'] as String,
            r['keterangan'] as String, r['nominal'] as int, r['waktu'] as String)
    ];
  }
}


class DiningService {
  final MahasiswaRepository _mhsRepo;
  final RiwayatRepository _riwayatRepo;
  final MetodePembayaran _pembayaran;
  final UnitOfWork _uow;

  DiningService(this._mhsRepo, this._riwayatRepo, this._pembayaran, this._uow);

  /// Simulasi tap kartu: potong deposito + catat riwayat dalam satu transaksi.
  String tapKartu(int idKartu, OpsiMakan opsi) {
    final biaya = opsi.hitungBiaya(); // polimorfisme
    try {
      return _uow.jalankan(() {
        final mhs = _mhsRepo.cariById(idKartu);
        _pembayaran.bayar(mhs, biaya);
        _mhsRepo.perbarui(mhs);
        _riwayatRepo.catat(idKartu, 'MAKAN', opsi.nama, -biaya);
        return 'OK  ${mhs.nama} makan ${opsi.nama}. '
            'Terpotong ${rupiah(biaya)} | Sisa deposito ${rupiah(mhs.deposito)}';
      });
    } on SaldoTidakCukupException {
      // transaksi sudah di-rollback; gagal tetap dicatat sebagai riwayat
      _riwayatRepo.catat(idKartu, 'GAGAL', '${opsi.nama} (saldo kurang)', 0);
      rethrow;
    }
  }

  void isiDeposito(int idKartu, int nominal) {
    _uow.jalankan(() {
      final mhs = _mhsRepo.cariById(idKartu);
      mhs.isiDeposito(nominal);
      _mhsRepo.perbarui(mhs);
      _riwayatRepo.catat(idKartu, 'TOPUP', 'Isi deposito', nominal);
    });
  }

  int cekSaldo(int idKartu) => _mhsRepo.cariById(idKartu).deposito;

  List<Transaksi> riwayat(int idKartu) {
    _mhsRepo.cariById(idKartu); // pastikan akun ada
    return _riwayatRepo.ambilPerAkun(idKartu);
  }

  List<Mahasiswa> daftar() => _mhsRepo.semua();
}


void isiDataAwal(MahasiswaRepository repo) {
  final data = [
    Mahasiswa(111, 'Rebecca', depositoAwal: 50000),
    Mahasiswa(169, 'Jennifer', depositoAwal: 100000),
    Mahasiswa(201, 'Rolas', depositoAwal: 30000),
    Mahasiswa(399, 'Ferdi', depositoAwal: 16000),
    Mahasiswa(104, 'Joana', depositoAwal: 10000),
    Mahasiswa(428, 'Marcel', depositoAwal: 40000),
  ];
  for (final m in data) {
    repo.tambahJikaBelum(m); // tidak menimpa data yang sudah ada
  }
}


void main() {
  final helper = DatabaseHelper();
  final mhsRepo = SqliteMahasiswaRepository(helper);
  final service = DiningService(
    mhsRepo,
    SqliteRiwayatRepository(helper),
    PembayaranDeposito(),
    helper,
  );

  try {
    isiDataAwal(mhsRepo);
  } on SqliteException catch (e) {
    print('Gagal menyiapkan database: $e');
    return;
  }

  print('=== DINING ASRAMA UNAI ===');
  var jalan = true;
  while (jalan) {
    print('\n1. Makan (tap kartu)');
    print('2. Isi deposito');
    print('3. Cek saldo');
    print('4. Daftar mahasiswa');
    print('5. Riwayat transaksi (pilih per akun)');
    print('6. Simulasi semua mahasiswa tap kartu');
    print('7. Reset data demo');
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
          _tampilDaftar(service);
          break;
        case '5':
          _tampilDaftar(service);
          final id = _bacaInt('Lihat riwayat akun dengan ID: ');
          final log = service.riwayat(id);
          print('\n--- Riwayat akun ID $id ---');
          if (log.isEmpty) print('Belum ada transaksi untuk akun ini.');
          for (final t in log) {
            print(t);
          }
          break;
        case '6':
          _simulasi(service);
          break;
        case '7':
          helper.resetData();
          isiDataAwal(mhsRepo);
          print('Data demo dikembalikan ke kondisi awal.');
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
    } on SqliteException catch (e) {
      print('Error database: $e');
    } catch (e) {
      print('Terjadi kesalahan tak terduga: $e');
    }
  }

  helper.tutup();
}

void _tampilDaftar(DiningService service) {
  print('\n--- Daftar mahasiswa ---');
  for (final m in service.daftar()) {
    final status = m.bisaMakan(15000) ? 'Aktif' : 'ISI ULANG!';
    print('${m.id} | ${m.nama.padRight(9)} | '
        '${rupiah(m.deposito).padRight(10)} | $status');
  }
}


void _simulasi(DiningService service) {
  for (final jenis in ['dine in', 'take away']) {
    print('\n--- Ronde: $jenis ---');
    for (final mhs in service.daftar()) {
      try {
        print(service.tapKartu(mhs.id, OpsiMakanFactory.buat(jenis)));
      } on DiningException catch (e) {
        print('XX  ${mhs.nama}: $e');
      }
    }
  }
}

int _bacaInt(String label) {
  stdout.write(label);
  return int.parse(stdin.readLineSync()?.trim() ?? '');
}