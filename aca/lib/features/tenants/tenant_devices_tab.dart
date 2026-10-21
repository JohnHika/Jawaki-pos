import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'tenant_widgets.dart';
import 'tenants_logic.dart';

/// Devices tab: the tills/phones registered to the company, with app versions.
class TenantDevicesTab extends StatefulWidget {
  const TenantDevicesTab({super.key, required this.tenantId, required this.refresh});

  final String tenantId;
  final Listenable refresh;

  @override
  State<TenantDevicesTab> createState() => _TenantDevicesTabState();
}

class _TenantDevicesTabState extends State<TenantDevicesTab> with TenantRefreshMixin {
  final _key = GlobalKey<LoadBuilderState<List<TenantDevice>>>();

  @override
  Listenable get refreshSignal => widget.refresh;

  @override
  void onRefreshSignal() => _key.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AcaRepository>();
    return LoadBuilder<List<TenantDevice>>(
      key: _key,
      load: () => repo.tenantDevices(widget.tenantId),
      emptyWhen: (d) => d.isEmpty,
      empty: const EmptyState(
        icon: Icons.phone_android_rounded,
        title: 'No devices registered',
        message: 'Devices appear here after someone signs in to Counterbase on a till or phone.',
      ),
      builder: (context, devices, reload) {
        final p = context.aca;
        final newest = newestVersion(devices.map((d) => d.appVersion));
        final behind = devices.where((d) => isOutdatedVersion(d.appVersion, newest)).length;
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kTabPadding,
          itemCount: devices.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  behind == 0
                      ? plural(devices.length, 'device')
                      : '${plural(devices.length, 'device')} · $behind not on the newest app version ($newest)',
                  style: TextStyle(color: behind == 0 ? p.textMuted : p.warning, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              );
            }
            final d = devices[i - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceCard(device: d, outdated: isOutdatedVersion(d.appVersion, newest), newest: newest),
            );
          },
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.outdated, required this.newest});

  final TenantDevice device;
  final bool outdated;
  final String? newest;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final d = device;
    final hardware = [
      if (d.model != null && d.model!.trim().isNotEmpty) d.model!.trim(),
      if (d.osVersion != null && d.osVersion!.trim().isNotEmpty) 'Android ${d.osVersion!.trim()}',
    ].join(' · ');
    final version = d.appVersion;
    return AcaCard(
      tone: outdated ? Tone.warning : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: p.surfaceHigh, shape: BoxShape.circle),
                child: Icon(Icons.phone_android_rounded, color: p.textMuted, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name.isEmpty ? 'Unnamed device' : d.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                    if (hardware.isNotEmpty)
                      Text(hardware, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 13)),
                  ],
                ),
              ),
              if (!d.isActive) const Padding(padding: EdgeInsets.only(left: 8), child: StatusPill('Disabled', tone: Tone.neutral, dense: true)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (d.branchName.isNotEmpty) StatusPill(d.branchName, tone: Tone.neutral, icon: Icons.storefront_outlined, dense: true),
              StatusPill(
                version == null || version.trim().isEmpty ? 'App version unknown' : 'App v$version',
                tone: outdated ? Tone.warning : Tone.neutral,
                icon: outdated ? Icons.system_update_rounded : null,
                dense: true,
              ),
            ],
          ),
          if (outdated) ...[
            const SizedBox(height: 6),
            Text('Newest on this company\'s devices is v$newest', style: TextStyle(color: p.warning, fontSize: 12.5)),
          ],
          const SizedBox(height: 8),
          Text('Last active ${Fmt.ago(d.lastActiveAt)}', style: TextStyle(fontSize: 12.5, color: p.textMuted)),
          const SizedBox(height: 2),
          Text('Last sync ${Fmt.ago(d.lastSyncAt)}', style: TextStyle(fontSize: 12.5, color: p.textMuted)),
        ],
      ),
    );
  }
}
