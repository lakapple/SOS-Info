import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/models/rescue_message.dart';
import '../../data/models/request_type.dart';
import '../../data/models/extracted_info.dart';
import '../../logic/providers/sms_provider.dart';

class SosCard extends ConsumerStatefulWidget {
  final RescueMessage message;
  final VoidCallback onMove;

  const SosCard({
    super.key, 
    required this.message, 
    required this.onMove
  });

  @override
  ConsumerState<SosCard> createState() => _SosCardState();
}

class _SosCardState extends ConsumerState<SosCard> {
  bool _isEditing = false;
  
  late TextEditingController _phoneCtrl;
  late TextEditingController _peopleCtrl;
  late TextEditingController _addrCtrl;
  late TextEditingController _contentCtrl;
  late RequestType _selectedType;
  
  double _lat = 0.0;
  double _lng = 0.0;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final info = widget.message.info;
    _phoneCtrl = TextEditingController(text: info.phoneNumbers.join(", "));
    _peopleCtrl = TextEditingController(text: info.peopleCount.toString());
    _addrCtrl = TextEditingController(text: info.address);
    _contentCtrl = TextEditingController(text: info.content);
    _selectedType = info.requestType;
    _lat = info.lat;
    _lng = info.lng;

    if (_lat == 0 && _lng == 0) {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
        if (_isEditing) _mapController.move(LatLng(_lat, _lng), 15);
      }
    } catch (_) {
      if (_lat == 0) setState(() { _lat = 21.0285; _lng = 105.8542; });
    }
  }

  @override
  void didUpdateWidget(covariant SosCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If update happens (AI finished), ONLY update fields if NOT editing
    // This prevents the AI from overwriting what you are currently typing
    if (oldWidget.message.info != widget.message.info && !_isEditing) {
      _initControllers();
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _peopleCtrl.dispose();
    _addrCtrl.dispose();
    _contentCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final newInfo = ExtractedInfo(
      phoneNumbers: _phoneCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      peopleCount: int.tryParse(_peopleCtrl.text) ?? 1,
      address: _addrCtrl.text,
      content: _contentCtrl.text,
      requestType: _selectedType,
      lat: _lat,
      lng: _lng,
      isAnalyzed: true,
    );

    // Saving will set hasManualOverride = true in the provider
    await ref.read(smsProvider.notifier).updateAndSave(widget.message, newInfo);

    if (mounted) {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Info Updated & AI Paused for this msg")));
    }
  }

  Future<void> _handleSendClick() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Send"),
        content: const Text("Are you sure you want to send this alert to the rescue map?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("SEND"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending...")));
      final success = await ref.read(smsProvider.notifier).sendAlert(widget.message);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Sent!")));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Failed to send")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.message.info;
    final isAnalyzing = widget.message.isAnalyzing; // Check message state

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.errorContainer,
      child: ExpansionTile(
        shape: const Border(), collapsedShape: const Border(),
        leading: isAnalyzing 
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.priority_high, color: Colors.red),
        
        title: Text(
          info.phoneNumbers.isNotEmpty ? info.phoneNumbers.first : widget.message.sender, 
          style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAnalyzing) 
              const Text("AI Analyzing...", style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
            
            Text(
              widget.message.originalMessage.body ?? "", 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis, 
            ),
          ],
        ),
        
        children: [
          // NON-BLOCKING LOADING INDICATOR
          if (isAnalyzing) const LinearProgressIndicator(minHeight: 2),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ALWAYS SHOW CONTENT AREA (View or Edit)
                _buildContentArea(), 

                const Text("Full Message:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
                  child: SelectableText(widget.message.originalMessage.body ?? "", style: const TextStyle(fontSize: 15)),
                ),
                
                const SizedBox(height: 15),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _isEditing ? _handleSave : () => setState(() => _isEditing = true),
                      icon: Icon(_isEditing ? Icons.save : Icons.edit, size: 18),
                      label: Text(_isEditing ? "SAVE" : "EDIT"),
                      style: TextButton.styleFrom(foregroundColor: Colors.blue[800]),
                    ),

                    const SizedBox(width: 8),

                    FilledButton.icon(
                      onPressed: widget.message.apiSent ? null : _handleSendClick,
                      icon: Icon(widget.message.apiSent ? Icons.check : Icons.cloud_upload),
                      label: Text(widget.message.apiSent ? "Sent" : "SEND ALERT"),
                      style: FilledButton.styleFrom(backgroundColor: widget.message.apiSent ? Colors.green : Colors.red),
                    ),

                    const SizedBox(width: 8),
                    
                    TextButton(onPressed: widget.onMove, child: const Text("Not SOS"))
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    if (_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: _phoneCtrl, decoration: _inputDec("Phones", Icons.phone), style: _inputStyle),
          const SizedBox(height: 8),
          DropdownButtonFormField<RequestType>(
            value: _selectedType,
            isExpanded: true,
            decoration: _inputDec("Type", Icons.category),
            items: RequestType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.vietnameseName))).toList(),
            onChanged: (v) => setState(() => _selectedType = v!),
          ),
          const SizedBox(height: 8),
          TextField(controller: _peopleCtrl, decoration: _inputDec("People", Icons.group), keyboardType: TextInputType.number, style: _inputStyle),
          const SizedBox(height: 8),
          TextField(controller: _addrCtrl, decoration: _inputDec("Address", Icons.location_on), maxLines: 2, minLines: 1, style: _inputStyle),
          
          const SizedBox(height: 12),
          const Text(" Pick Location:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Container(
            height: 200,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(_lat, _lng),
                  initialZoom: 15,
                  onTap: (_, point) => setState(() { _lat = point.latitude; _lng = point.longitude; }),
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_lat, _lng),
                        width: 40, height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text("Use My Current Location"),
              onPressed: () {
                _getCurrentLocation().then((_) {
                  _mapController.move(LatLng(_lat, _lng), 15);
                });
              },
            ),
          ),

          const SizedBox(height: 8),
          TextField(controller: _contentCtrl, decoration: _inputDec("Content", Icons.description), maxLines: 4, minLines: 1, style: _inputStyle),
          const SizedBox(height: 15),
        ],
      );
    } else {
      // VIEW MODE (Now accessible even if loading)
      final info = widget.message.info;
      return Column(
        children: [
          _row(Icons.phone, "Phones", info.phoneNumbers.join(", "), Colors.blue), const Divider(),
          _row(Icons.category, "Type", info.requestType.vietnameseName, Colors.purple), const Divider(),
          _row(Icons.group, "People", "${info.peopleCount}", Colors.orange), const Divider(),
          _row(Icons.location_on, "Address", info.address, Colors.red), const Divider(),
          _row(Icons.map, "Location", "${info.lat.toStringAsFixed(5)}, ${info.lng.toStringAsFixed(5)}", Colors.green), const Divider(),
          _row(Icons.description, "Content", info.content, Colors.black87), const SizedBox(height: 15),
        ],
      );
    }
  }

  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
    labelText: label, icon: Icon(icon, size: 20), isDense: true, 
    border: const OutlineInputBorder(), contentPadding: const EdgeInsets.all(8)
  );
  
  final TextStyle _inputStyle = const TextStyle(fontSize: 14, fontWeight: FontWeight.bold);

  Widget _row(IconData icon, String label, String val, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: color), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(val.isEmpty ? "-" : val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))
      ]))
    ]);
  }
}