import 'package:flutter/material.dart';
import '../../data/models/rescue_message.dart';
import '../../data/models/request_type.dart';

class SosCard extends StatelessWidget {
  final RescueMessage message;
  final Function(RescueMessage) onManualSend;
  final Function(RescueMessage) onMove;

  const SosCard({
    super.key, 
    required this.message, 
    required this.onManualSend, 
    required this.onMove
  });

  @override
  Widget build(BuildContext context) {
    final info = message.info;
    
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias, // Ensures clean rounded corners
      color: Theme.of(context).colorScheme.errorContainer,
      child: ExpansionTile(
        // --- FIX 1: REMOVE BLACK LINES (BORDERS) ---
        shape: const Border(), 
        collapsedShape: const Border(),
        
        leading: message.isAnalyzing 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.priority_high, color: Colors.red),
            
        title: Text(
          info.phoneNumbers.isNotEmpty ? info.phoneNumbers.first : (message.originalMessage.address ?? "Unknown"), 
          style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        
        subtitle: Text(
          !info.isAnalyzed ? "Analyzing..." : info.content, 
          maxLines: 1, 
          overflow: TextOverflow.ellipsis
        ),
        
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- FIX 2: SHOW RAW TEXT EVEN IF LOADING ---
                if (!info.isAnalyzed) ...[
                  const Center(child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  )),
                  const Center(child: Text("AI is analyzing content...", style: TextStyle(fontSize: 12, color: Colors.grey))),
                  const SizedBox(height: 15),
                ] else ...[
                  // GEMINI EXTRACTED DATA
                  _buildInfoRow(Icons.phone, "Phones", info.phoneNumbers.join(", "), Colors.blue),
                  const Divider(),
                  _buildInfoRow(Icons.category, "Type", info.requestType.vietnameseName, Colors.purple),
                  const Divider(),
                  _buildInfoRow(Icons.location_on, "Address", info.address, Colors.red),
                  const Divider(),
                  _buildInfoRow(Icons.summarize, "Help Content", info.content, Colors.black87),
                  const Divider(),
                  _buildInfoRow(Icons.group, "People", "${info.peopleCount}", Colors.orange),
                  const SizedBox(height: 15),
                ],

                // --- FIX 3: RAW MESSAGE SECTION (ALWAYS VISIBLE) ---
                const Text("Original Message:", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white, // Clean white box like Other Tab
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    message.originalMessage.body ?? "", 
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ),
                
                const SizedBox(height: 15),
                
                // BUTTONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Only show Send button if analysis is done
                    if (info.isAnalyzed)
                      FilledButton.icon(
                        onPressed: message.apiSent ? null : () => onManualSend(message),
                        icon: Icon(message.apiSent ? Icons.check : Icons.cloud_upload),
                        label: Text(message.apiSent ? "Sent" : "SEND ALERT"),
                        style: FilledButton.styleFrom(backgroundColor: message.apiSent ? Colors.green : Colors.red),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => onMove(message), 
                      child: const Text("Not SOS")
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ]))
    ]);
  }
}