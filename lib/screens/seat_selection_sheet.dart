import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/seat.dart';
import '../services/seat_service.dart';

class SeatSelectionResult {
  final String tableId;
  final List<String> seatIds;
  final String tableLabel; // e.g. "Table T1"
  final List<String> seatLabels; // e.g. ["Seat A1", "Seat A2"]
  final String startTime; // e.g. "14:00"
  final String endTime; // e.g. "16:00"

  const SeatSelectionResult({
    required this.tableId,
    required this.seatIds,
    required this.tableLabel,
    required this.seatLabels,
    required this.startTime,
    required this.endTime,
  });
}

class SeatSelectionSheet extends StatefulWidget {
  final String studySpotId; // ← NEW: passed in from HomeScreen

  const SeatSelectionSheet({super.key, required this.studySpotId});

  @override
  State<SeatSelectionSheet> createState() => SeatSelectionSheetState();
}

class SeatSelectionSheetState extends State<SeatSelectionSheet> {
  // ── State ─────────────────────────────────────────────────────────────────
  List<StudySpotTable> _tables = [];
  int _selectedTableIndex = 0;
  bool _isLoadingTables = true;

  // Live seats for the currently selected table
  List<Seat> _seats = [];
  StreamSubscription<List<Seat>>? _seatsSub;

  // Selected seat IDs (UUIDs from DB, not indices)
  final Set<String> _selectedSeatIds = {};
  String selectedStartTime = "Select Time";
  String selectedEndTime = "Select Time";
  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  @override
  void dispose() {
    _seatsSub?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  bool _isTableSelectable(StudySpotTable table) =>
      table.tableStatus == 'available';

  Color _tableStatusColor(String status) {
    switch (status) {
      case 'reserved':
        return Colors.orange.shade300;
      case 'occupied':
        return Colors.red.shade300;
      case 'maintenance':
        return Colors.grey.shade500;
      default:
        return Colors.green.shade300;
    }
  }

  String _tableStatusLabel(String status) {
    switch (status) {
      case 'reserved':
        return 'Reserved';
      case 'occupied':
        return 'Occupied';
      case 'maintenance':
        return 'Maintenance';
      default:
        return 'Available';
    }
  }

  Future<void> _loadTables() async {
    try {
      final tables = await SeatService.fetchTablesWithSeats(widget.studySpotId);
      if (!mounted) return;

      setState(() {
        _tables = tables;

        _selectedTableIndex = 0;
        _isLoadingTables = false;
      });

      if (tables.isNotEmpty) {
        _subscribeToSeats(tables[0].id);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTables = false);
    }
  }

  void _subscribeToSeats(String tableId) {
    _seatsSub?.cancel();
    _selectedSeatIds.clear();
    _seatsSub = SeatService.seatsStream(tableId).listen((seats) {
      if (mounted) setState(() => _seats = seats);
    });
  }

  void _onTableSelected(int index) {
    setState(() {
      _selectedTableIndex = index;
      _selectedSeatIds.clear();
    });
    _subscribeToSeats(_tables[index].id);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  bool _isOccupied(Seat seat) =>
      seat.seatStatus == 'occupied' || seat.seatStatus == 'reserved';

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Table & Seat',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoadingTables)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_tables.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'No tables available at this spot.',
                  style: GoogleFonts.inter(color: Colors.grey),
                ),
              ),
            )
          else ...[
            // ── Table Selector ───────────────────────────────────────────
            Text(
              'Select Table',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_tables.length, (index) {
                  final table = _tables[index];
                  final isSelected = _selectedTableIndex == index;
                  final isUnavailable =
                      table.tableStatus == 'occupied' ||
                      table.tableStatus == 'maintenance';
                  final selectable = !isUnavailable;
                  final statusLabel = _tableStatusLabel(table.tableStatus);
                  final statusColor = _tableStatusColor(table.tableStatus);

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Table ${table.tableNumber}'),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                statusLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: selectable
                                      ? statusColor
                                      : Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (isUnavailable)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Unavailable',
                                      style: GoogleFonts.inter(
                                        fontSize: 8,
                                        color: Colors.red.shade700,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: selectable
                          ? (selected) {
                              if (selected) _onTableSelected(index);
                            }
                          : null,
                      backgroundColor: selectable
                          ? Colors.grey[100]
                          : Colors.grey[300],
                      selectedColor: const Color(
                        0xFF2563EB,
                      ).withValues(alpha: 0.18),
                      labelStyle: GoogleFonts.inter(
                        color: isSelected
                            ? const Color(0xFF2563EB)
                            : selectable
                            ? Colors.black87
                            : Colors.grey[700],
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF2563EB)
                            : Colors.grey.shade400,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),

            if (!_isTableSelectable(_tables[_selectedTableIndex]) &&
                _tables.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'This table is ${_tableStatusLabel(_tables[_selectedTableIndex].tableStatus).toLowerCase()}. You can still view its seats, but you cannot reserve this table.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ),

            // ── Seat Grid ────────────────────────────────────────────────
            Text(
              'Select Seat',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            if (_seats.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Loading seats…',
                    style: GoogleFonts.inter(color: Colors.grey),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _seats.length,
                itemBuilder: (context, index) {
                  final seat = _seats[index];
                  final occupied = _isOccupied(seat);
                  final selected = _selectedSeatIds.contains(seat.id);

                  return GestureDetector(
                    onTap: occupied
                        ? null
                        : () {
                            setState(() {
                              if (selected) {
                                _selectedSeatIds.remove(seat.id);
                              } else {
                                _selectedSeatIds.add(seat.id);
                              }
                            });
                          },
                    child: Container(
                      decoration: BoxDecoration(
                        color: occupied
                            ? Colors.grey[300]
                            : selected
                            ? const Color(0xFF2563EB)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: occupied
                              ? Colors.transparent
                              : selected
                              ? const Color(0xFF2563EB)
                              : Colors.grey[400]!,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Seat ${seat.seatNumber}',
                            style: GoogleFonts.inter(
                              color: occupied
                                  ? Colors.grey[600]
                                  : selected
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                          if (occupied)
                            Text(
                              seat.seatStatus == 'reserved'
                                  ? 'Reserved'
                                  : 'Occupied',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 16),

            // ── Legend ───────────────────────────────────────────────────
            Row(
              children: [
                _buildLegendDot(Colors.white, Colors.grey, 'Available'),
                const SizedBox(width: 16),
                _buildLegendDot(
                  const Color(0xFF2563EB),
                  Colors.transparent,
                  'Selected',
                ),
                const SizedBox(width: 16),
                _buildLegendDot(
                  Colors.grey.shade300,
                  Colors.transparent,
                  'Unavailable',
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Time Picker ───────────────────────────────────────────────
            Text(
              'Select Time',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Start Time
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        helpText: 'Select Start Time',
                      );
                      if (picked != null) {
                        setState(() {
                          selectedStartTime =
                              '${picked.hour.toString().padLeft(2, '0')}:'
                              '${picked.minute.toString().padLeft(2, '0')}';
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: selectedStartTime == 'Select Time'
                            ? Colors.grey[100]
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedStartTime == 'Select Time'
                              ? Colors.grey[300]!
                              : const Color(0xFF2563EB),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 18,
                            color: selectedStartTime == 'Select Time'
                                ? Colors.grey[500]
                                : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Start',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  selectedStartTime == 'Select Time'
                                      ? 'Tap to set'
                                      : selectedStartTime,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: selectedStartTime == 'Select Time'
                                        ? Colors.grey[400]
                                        : const Color(0xFF1E3A5F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // End Time
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        helpText: 'Select End Time',
                      );
                      if (picked != null) {
                        setState(() {
                          selectedEndTime =
                              '${picked.hour.toString().padLeft(2, '0')}:'
                              '${picked.minute.toString().padLeft(2, '0')}';
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: selectedEndTime == 'Select Time'
                            ? Colors.grey[100]
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedEndTime == 'Select Time'
                              ? Colors.grey[300]!
                              : const Color(0xFF2563EB),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time_filled_rounded,
                            size: 18,
                            color: selectedEndTime == 'Select Time'
                                ? Colors.grey[500]
                                : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'End',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  selectedEndTime == 'Select Time'
                                      ? 'Tap to set'
                                      : selectedEndTime,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: selectedEndTime == 'Select Time'
                                        ? Colors.grey[400]
                                        : const Color(0xFF1E3A5F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Confirm Button ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _selectedSeatIds.isEmpty ||
                        selectedStartTime == 'Select Time' ||
                        selectedEndTime == 'Select Time'
                    ? null
                    : () {
                        // Return the selected table ID and seat IDs to caller.
                        final selectedTable = _tables[_selectedTableIndex];
                        final selectedSeats = _seats
                            .where((s) => _selectedSeatIds.contains(s.id))
                            .toList();
                        Navigator.pop(
                          context,
                          SeatSelectionResult(
                            tableId: selectedTable.id,
                            seatIds: _selectedSeatIds.toList(),
                            tableLabel: 'Table ${selectedTable.tableNumber}',
                            seatLabels: selectedSeats
                                .map((s) => 'Seat ${s.seatNumber}')
                                .toList(),
                            startTime: selectedStartTime,
                            endTime: selectedEndTime,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: Text(
                  _selectedSeatIds.isEmpty
                      ? 'Select a seat to continue'
                      : (selectedStartTime == 'Select Time' ||
                            selectedEndTime == 'Select Time')
                      ? 'Select a start & end time to continue'
                      : 'Confirm ${_selectedSeatIds.length} Seat(s)',
                  style: GoogleFonts.inter(
                    color: _selectedSeatIds.isEmpty
                        ? Colors.grey[600]
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color fill, Color border, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: border == Colors.transparent ? fill : border,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }
}
