import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class ManageRoutersScreen extends StatelessWidget {
  const ManageRoutersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final List<model.Router> routers = appState.routers;
        final String? selectedId = appState.selectedRouter?.id;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: const LuciAppBar(title: 'Routers'),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => appState.loadRouters(),
                    child: routers.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
                                child: Text(
                                  'No routers added yet.',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 16, bottom: 24),
                            itemCount: routers.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final model.Router router = routers[index];
                              final bool isSelected = router.id == selectedId;
                              String routerTitle;
                              bool isStale = false;
                              if (isSelected && appState.dashboardData != null) {
                                final boardInfo = appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
                                final hostname = boardInfo?['hostname']?.toString();
                                routerTitle = (hostname != null && hostname.isNotEmpty)
                                    ? hostname
                                    : (router.lastKnownHostname ?? router.ipAddress);
                              } else if (router.lastKnownHostname != null && router.lastKnownHostname!.isNotEmpty) {
                                routerTitle = router.lastKnownHostname!;
                                isStale = true;
                              } else {
                                routerTitle = router.ipAddress;
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(18.0),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18.0),
                                    onTap: () {
                                      if (!isSelected) appState.selectRouter(router.id);
                                    },
                                    child: Card(
                                      elevation: isSelected ? 6 : 2,
                                      margin: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18.0),
                                        side: BorderSide(
                                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
                                          width: 1,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          leading: Container(
                                            padding: const EdgeInsets.all(8.0),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.13),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.router,
                                              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                                              size: 22,
                                              semanticLabel: 'Router icon',
                                            ),
                                          ),
                                          title: Align(
                                            alignment: Alignment.centerLeft,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 180),
                                              child: Tooltip(
                                                message: isStale ? 'Last known hostname (may be out of date)' : '',
                                                child: Text(
                                                  routerTitle,
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: isStale
                                                        ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                                                        : Theme.of(context).colorScheme.onSurface,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 4.0),
                                            child: Text(
                                              '${router.ipAddress} (${router.username})',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isSelected)
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 8.0),
                                                  child: Chip(
                                                    label: const Text('Active'),
                                                    labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
                                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                                    visualDensity: VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline),
                                                tooltip: 'Remove',
                                                onPressed: () async {
                                                  String routerLabel;
                                                  if (isSelected && appState.dashboardData != null) {
                                                    final boardInfo = appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
                                                    final hostname = boardInfo?['hostname']?.toString();
                                                    routerLabel = (hostname != null && hostname.isNotEmpty)
                                                        ? hostname
                                                        : router.ipAddress;
                                                  } else {
                                                    routerLabel = router.ipAddress;
                                                  }
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: const Text('Remove Router'),
                                                      content: Text('Are you sure you want to remove $routerLabel?'),
                                                      actions: [
                                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                                                      ],
                                                    ),
                                                  );
                                                  if (!context.mounted) return;
                                                  if (confirm == true) {
                                                    appState.removeRouter(router.id);
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 24, thickness: 1),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Add Router'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final ipController = TextEditingController();
                            final userController = TextEditingController(text: 'root');
                            final passController = TextEditingController();
                            final formKey = GlobalKey<FormState>();
                            bool useHttps = false;
                            bool obscureText = true;
                            String? errorMessage;
                            await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (context) {
                                return StatefulBuilder(
                                  builder: (context, setState) {
                                    return AlertDialog(
                                      title: const Text('Add Router'),
                                      content: Form(
                                        key: formKey,
                                        child: SingleChildScrollView(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextFormField(
                                                controller: ipController,
                                                decoration: const InputDecoration(labelText: 'IP Address or Hostname'),
                                                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                                autofillHints: const [AutofillHints.url, AutofillHints.username],
                                              ),
                                              const SizedBox(height: 8),
                                              TextFormField(
                                                controller: userController,
                                                decoration: const InputDecoration(labelText: 'Username'),
                                                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                                autofillHints: const [AutofillHints.username],
                                              ),
                                              const SizedBox(height: 8),
                                              TextFormField(
                                                controller: passController,
                                                decoration: InputDecoration(
                                                  labelText: 'Password',
                                                  suffixIcon: IconButton(
                                                    icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
                                                    onPressed: () => setState(() => obscureText = !obscureText),
                                                    tooltip: obscureText ? 'Show password' : 'Hide password',
                                                  ),
                                                ),
                                                obscureText: obscureText,
                                                autofillHints: const [AutofillHints.password],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Checkbox(
                                                    value: useHttps,
                                                    onChanged: (v) {
                                                      setState(() {
                                                        useHttps = v ?? false;
                                                      });
                                                    },
                                                  ),
                                                  const Text('Use HTTPS'),
                                                ],
                                              ),
                                              if (errorMessage != null) ...[
                                                const SizedBox(height: 12),
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.error_outline_rounded,
                                                        color: Theme.of(context).colorScheme.error,
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          errorMessage!,
                                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                            color: Theme.of(context).colorScheme.error,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                        TextButton(
                                          onPressed: () async {
                                            if (formKey.currentState!.validate()) {
                                              final ip = ipController.text.trim();
                                              final user = userController.text.trim();
                                              final pass = passController.text;
                                              final id = '$ip-$user';
                                              if (routers.any((r) => r.id == id)) {
                                                setState(() {
                                                  errorMessage = 'Router already exists.';
                                                });
                                                return;
                                              }
                                              // Always fetch hostname from router after login
                                              final newRouter = model.Router(
                                                id: id,
                                                ipAddress: ip,
                                                username: user,
                                                password: pass,
                                                useHttps: useHttps,
                                              );
                                              await appState.addRouter(newRouter);
                                              if (!context.mounted) return;
                                              // Automatically select the new router after adding
                                              await appState.selectRouter(newRouter.id);
                                              if (!context.mounted) return;
                                              Navigator.pop(context);
                                            }
                                          },
                                          child: const Text('Add'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                            if (!context.mounted) return;
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 