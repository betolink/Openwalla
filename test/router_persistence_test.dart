import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/models/router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Router Persistence Tests', () {
    late RouterService routerService;
    late SecureStorageService storageService;

    setUp(() {
      // Clear any existing data
      FlutterSecureStorage.setMockInitialValues({});
      routerService = RouterService();
      storageService = SecureStorageService();
    });

    test('Should persist selected router across app restarts', () async {
      // Create test routers
      final router1 = Router(
        id: '192.168.1.1-admin',
        ipAddress: '192.168.1.1',
        username: 'admin',
        password: 'password',
        useHttps: false,
      );
      
      final router2 = Router(
        id: '192.168.1.2-root',
        ipAddress: '192.168.1.2',
        username: 'root',
        password: 'password',
        useHttps: true,
      );

      // Add routers and select the second one
      await routerService.addRouter(router1);
      await routerService.addRouter(router2);
      routerService.selectRouter(router2.id);
      
      // Verify router2 is selected
      expect(routerService.selectedRouter?.id, equals(router2.id));
      
      // Simulate app restart by creating a new service instance
      final newRouterService = RouterService();
      await newRouterService.loadRouters();
      
      // Verify the selected router is persisted
      expect(newRouterService.selectedRouter?.id, equals(router2.id));
      expect(newRouterService.selectedRouter?.ipAddress, equals('192.168.1.2'));
    });

    test('Should handle missing selected router gracefully', () async {
      // Add a router
      final router = Router(
        id: '192.168.1.1-admin',
        ipAddress: '192.168.1.1',
        username: 'admin',
        password: 'password',
        useHttps: false,
      );
      
      await routerService.addRouter(router);
      routerService.selectRouter(router.id);
      
      // Remove the router
      await routerService.removeRouter(router.id);
      
      // Add a new router
      final newRouter = Router(
        id: '192.168.1.2-root',
        ipAddress: '192.168.1.2',
        username: 'root',
        password: 'password',
        useHttps: true,
      );
      await routerService.addRouter(newRouter);
      
      // Simulate app restart
      final newRouterService = RouterService();
      await newRouterService.loadRouters();
      
      // Should default to the only available router
      expect(newRouterService.selectedRouter?.id, equals(newRouter.id));
    });

    test('Should clear selected router when all routers are removed', () async {
      // Add and select a router
      final router = Router(
        id: '192.168.1.1-admin',
        ipAddress: '192.168.1.1',
        username: 'admin',
        password: 'password',
        useHttps: false,
      );
      
      await routerService.addRouter(router);
      routerService.selectRouter(router.id);
      
      // Remove all routers
      await routerService.removeRouter(router.id);
      
      // Simulate app restart
      final newRouterService = RouterService();
      await newRouterService.loadRouters();
      
      // Should have no selected router
      expect(newRouterService.selectedRouter, isNull);
      expect(newRouterService.routers, isEmpty);
    });
  });
}