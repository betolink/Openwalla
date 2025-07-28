import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/services/secure_storage_service.dart';

class RouterService {
  final SecureStorageService _secureStorageService = SecureStorageService();
  
  List<model.Router> _routers = [];
  model.Router? _selectedRouter;

  List<model.Router> get routers => _routers;
  model.Router? get selectedRouter => _selectedRouter;

  Future<void> loadRouters() async {
    _routers = await _secureStorageService.getRouters();
    if (_routers.isNotEmpty && _selectedRouter == null) {
      _selectedRouter = _routers.first;
    }
  }

  Future<void> addRouter(model.Router router) async {
    _routers.add(router);
    await _secureStorageService.saveRouters(_routers);
    _selectedRouter ??= router;
  }

  Future<bool> removeRouter(String id) async {
    final wasActive = _selectedRouter?.id == id;
    _routers.removeWhere((r) => r.id == id);
    await _secureStorageService.saveRouters(_routers);
    
    if (wasActive) {
      if (_routers.isNotEmpty) {
        _selectedRouter = _routers.first;
        return true; // Indicates need to switch to new router
      } else {
        _selectedRouter = null;
        return false; // No routers available
      }
    }
    return false; // No router switch needed
  }

  model.Router? selectRouter(String id) {
    if (_routers.isEmpty) return null;
    
    final found = _routers.firstWhere(
      (r) => r.id == id,
      orElse: () => _routers.first,
    );
    
    _selectedRouter = found;
    return found;
  }

  Future<void> updateRouter(model.Router router) async {
    final idx = _routers.indexWhere((r) => r.id == router.id);
    if (idx != -1) {
      _routers[idx] = router;
      if (_selectedRouter?.id == router.id) {
        _selectedRouter = router;
      }
      await _secureStorageService.saveRouters(_routers);
    }
  }

  Future<void> updateSelectedRouterHostname(String hostname) async {
    if (_selectedRouter != null && hostname.isNotEmpty) {
      final idx = _routers.indexWhere((r) => r.id == _selectedRouter!.id);
      if (idx != -1) {
        _routers[idx] = _routers[idx].copyWith(lastKnownHostname: hostname);
        _selectedRouter = _routers[idx];
        await _secureStorageService.saveRouters(_routers);
      }
    }
  }

  model.Router createRouter(String ip, String user, String pass, bool useHttps) {
    final id = '$ip-$user';
    return model.Router(
      id: id,
      ipAddress: ip,
      username: user,
      password: pass,
      useHttps: useHttps,
    );
  }
}