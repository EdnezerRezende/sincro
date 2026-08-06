import 'package:geolocator/geolocator.dart';

enum LocationPermissionResult { granted, denied, deniedForever, serviceDisabled }

class LocationService {
  Future<LocationPermissionResult> solicitarPermissao() async {
    final servicoAtivo = await Geolocator.isLocationServiceEnabled();
    if (!servicoAtivo) return LocationPermissionResult.serviceDisabled;

    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (permissao == LocationPermission.denied) return LocationPermissionResult.denied;
    if (permissao == LocationPermission.deniedForever) return LocationPermissionResult.deniedForever;
    return LocationPermissionResult.granted;
  }

  Future<Position> obterPosicaoAtual() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
  }

  Future<void> abrirConfiguracoesDoApp() => Geolocator.openAppSettings();
}
