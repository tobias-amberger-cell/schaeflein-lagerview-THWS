import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

/// Wiederverwendbare, kompakte Datentabelle im Streamlit-Look:
/// Sticky-Header, beidseitig scrollbar, dünner Rahmen, helle Kopfzeile.
class AppFlatDataTable extends StatefulWidget {
  const AppFlatDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.height = 440,
    this.minWidth = 900,
    this.headingRowHeight = 36,
    this.dataRowHeight = 32,
    this.columnSpacing = 24,
    this.horizontalMargin = 12,
  });

  final List<DataColumn2> columns;
  final List<DataRow> rows;
  final double height;
  final double minWidth;
  final double headingRowHeight;
  final double dataRowHeight;
  final double columnSpacing;
  final double horizontalMargin;

  @override
  State<AppFlatDataTable> createState() => _AppFlatDataTableState();
}

class _AppFlatDataTableState extends State<AppFlatDataTable> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.6);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: widget.height,
          child: DataTable2(
            scrollController: _verticalController,
            horizontalScrollController: _horizontalController,
            isVerticalScrollBarVisible: true,
            isHorizontalScrollBarVisible: true,
            fixedTopRows: 1,
            minWidth: widget.minWidth,
            headingRowColor: WidgetStateProperty.all(
              colorScheme.surfaceContainerHigh,
            ),
            headingTextStyle: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              letterSpacing: 0.4,
            ),
            dataTextStyle: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
            ),
            headingRowHeight: widget.headingRowHeight,
            dataRowHeight: widget.dataRowHeight,
            columnSpacing: widget.columnSpacing,
            horizontalMargin: widget.horizontalMargin,
            dividerThickness: 0.5,
            bottomMargin: 0,
            columns: widget.columns,
            rows: widget.rows,
          ),
        ),
      ),
    );
  }
}
