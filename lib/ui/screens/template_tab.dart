import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/request_type.dart';

class TemplateTab extends StatefulWidget {
  const TemplateTab({super.key});
  @override
  State<TemplateTab> createState() => _TemplateTabState();
}

class _TemplateTabState extends State<TemplateTab> {
  final _phones = TextEditingController();
  final _people = TextEditingController(text: "1");
  final _addr = TextEditingController();
  final _content = TextEditingController();
  RequestType _type = RequestType.CUSTOM;
  double _lat = 0.0, _lng = 0.0;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      if(mounted) {
        setState(() { _lat = pos.latitude; _lng = pos.longitude; });
        _map.move(LatLng(_lat, _lng), 15);
      }
    } catch (_) {}
  }

  void _launch() async {
    final body = "sostemplate : ${_phones.text} : ${_type.name} : ${_people.text} : ${_addr.text} : $_lat-$_lng : ${_content.text}";
    final uri = Uri(scheme: 'sms', path: '', queryParameters: {'body': body});
    if (!await launchUrl(uri)) if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error launching SMS")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Template Creator")),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: _phones, decoration: _dec("Phones", Icons.phone), keyboardType: TextInputType.phone), const SizedBox(height: 10),
        DropdownButtonFormField<RequestType>(
          value: _type, decoration: _dec("Type", Icons.category),
          items: RequestType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.vietnameseName))).toList(),
          onChanged: (v) => setState(() => _type = v!),
        ), const SizedBox(height: 10),
        TextField(controller: _people, decoration: _dec("People", Icons.group), keyboardType: TextInputType.number), const SizedBox(height: 10),
        TextField(controller: _addr, decoration: _dec("Address", Icons.location_on)), const SizedBox(height: 15),
        const Text("Coordinates:", style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 5),
        SizedBox(height: 200, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: LatLng(21.0, 105.8), initialZoom: 15, onTap: (_, p) => setState(() { _lat = p.latitude; _lng = p.longitude; })),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
            MarkerLayer(markers: [Marker(point: LatLng(_lat, _lng), width: 40, height: 40, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: Colors.blue, size: 40))])
          ],
        ))),
        Center(child: Text("Lat: $_lat, Lng: $_lng", style: const TextStyle(color: Colors.grey))), const SizedBox(height: 10),
        TextField(controller: _content, decoration: _dec("Content", Icons.description), maxLines: 3), const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(onPressed: _launch, icon: const Icon(Icons.send), label: const Text("OPEN SMS APP")))
      ])),
    );
  }
  InputDecoration _dec(String l, IconData i) => InputDecoration(labelText: l, prefixIcon: Icon(i), border: const OutlineInputBorder(), isDense: true);
}