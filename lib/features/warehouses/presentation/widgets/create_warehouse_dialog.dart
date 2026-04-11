import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/warehouse.dart';

class NewWarehouseInput {
  const NewWarehouseInput({
    required this.name,
    required this.location,
    required this.status,
    required this.description,
    required this.lengthM,
    required this.widthM,
    required this.heightM,
    required this.rackRowCount,
    required this.rackLengthM,
    required this.rackWidthM,
    required this.rackLevels,
    required this.aisleWidthM,
    required this.zoneNames,
  });

  final String name;
  final String location;
  final WarehouseStatus status;
  final String description;
  final double lengthM;
  final double widthM;
  final double heightM;
  final int rackRowCount;
  final double rackLengthM;
  final double rackWidthM;
  final int rackLevels;
  final double aisleWidthM;
  final List<String> zoneNames;

  factory NewWarehouseInput.fromWarehouse(Warehouse warehouse) {
    final spec = warehouse.layoutSpec;
    return NewWarehouseInput(
      name: warehouse.name,
      location: warehouse.location,
      status: warehouse.status,
      description: warehouse.description,
      lengthM: spec?.lengthM ?? 60,
      widthM: spec?.widthM ?? 40,
      heightM: spec?.heightM ?? 12,
      rackRowCount: spec?.rackRowCount ?? 8,
      rackLengthM: spec?.rackLengthM ?? 18,
      rackWidthM: spec?.rackWidthM ?? 2.8,
      rackLevels: spec?.rackLevels ?? 4,
      aisleWidthM: spec?.aisleWidthM ?? 3.2,
      zoneNames: spec?.zoneNames ?? warehouse.zones.map((zone) => zone.name).toList(growable: false),
    );
  }
}

Future<NewWarehouseInput?> showCreateWarehouseDialog(BuildContext context) {
  return showDialog<NewWarehouseInput>(
    context: context,
    builder: (context) => const _WarehouseFormDialog(
      titleKey: 'newWarehouseTitle',
      submitKey: 'createWarehouse',
    ),
  );
}

Future<NewWarehouseInput?> showEditWarehouseDialog(
  BuildContext context,
  Warehouse warehouse,
) {
  return showDialog<NewWarehouseInput>(
    context: context,
    builder: (context) => _WarehouseFormDialog(
      titleKey: 'editWarehouseTitle',
      submitKey: 'saveChanges',
      initialInput: NewWarehouseInput.fromWarehouse(warehouse),
    ),
  );
}

class _WarehouseFormDialog extends StatefulWidget {
  const _WarehouseFormDialog({
    required this.titleKey,
    required this.submitKey,
    this.initialInput,
  });

  final String titleKey;
  final String submitKey;
  final NewWarehouseInput? initialInput;

  @override
  State<_WarehouseFormDialog> createState() => _WarehouseFormDialogState();
}

class _WarehouseFormDialogState extends State<_WarehouseFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _descriptionController;

  late final TextEditingController _lengthController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  late final TextEditingController _rackRowsController;
  late final TextEditingController _rackLengthController;
  late final TextEditingController _rackWidthController;
  late final TextEditingController _rackLevelsController;
  late final TextEditingController _aisleWidthController;
  late final TextEditingController _zonesController;

  late WarehouseStatus _status;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialInput;

    _nameController = TextEditingController(text: initial?.name ?? '');
    _locationController = TextEditingController(text: initial?.location ?? '');
    _descriptionController = TextEditingController(text: initial?.description ?? '');

    _lengthController = TextEditingController(text: _doubleToText(initial?.lengthM ?? 60));
    _widthController = TextEditingController(text: _doubleToText(initial?.widthM ?? 40));
    _heightController = TextEditingController(text: _doubleToText(initial?.heightM ?? 12));

    _rackRowsController = TextEditingController(text: '${initial?.rackRowCount ?? 8}');
    _rackLengthController = TextEditingController(text: _doubleToText(initial?.rackLengthM ?? 18));
    _rackWidthController = TextEditingController(text: _doubleToText(initial?.rackWidthM ?? 2.8));
    _rackLevelsController = TextEditingController(text: '${initial?.rackLevels ?? 4}');
    _aisleWidthController = TextEditingController(text: _doubleToText(initial?.aisleWidthM ?? 3.2));
    _zonesController = TextEditingController(
      text: (initial?.zoneNames.isNotEmpty ?? false)
          ? initial!.zoneNames.join(', ')
          : 'Wareneingang, Kommissionierung, Versand',
    );

    _status = initial?.status ?? WarehouseStatus.online;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _rackRowsController.dispose();
    _rackLengthController.dispose();
    _rackWidthController.dispose();
    _rackLevelsController.dispose();
    _aisleWidthController.dispose();
    _zonesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(widget.titleKey)),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(text: context.tr('warehouseBaseData')),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: context.tr('warehouseNameLabel')),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return context.tr('enterWarehouseName');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(labelText: context.tr('warehouseLocationLabel')),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return context.tr('enterWarehouseLocation');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<WarehouseStatus>(
                  initialValue: _status,
                  decoration: InputDecoration(labelText: context.tr('warehouseStatusLabel')),
                  items: WarehouseStatus.values
                      .map(
                        (status) => DropdownMenuItem<WarehouseStatus>(
                          value: status,
                          child: Text(context.tr(status.labelKey)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _status = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: context.tr('warehouseDescriptionLabel')),
                ),
                const SizedBox(height: AppSpacing.md),
                _SectionTitle(text: context.tr('warehouseLayoutData')),
                _TwoColumnNumberFields(
                  left: _DecimalFieldConfig(
                    controller: _lengthController,
                    label: context.tr('warehouseLengthLabel'),
                    validator: (value) => _validateDouble(context, value, min: 1),
                  ),
                  right: _DecimalFieldConfig(
                    controller: _widthController,
                    label: context.tr('warehouseWidthLabel'),
                    validator: (value) => _validateDouble(context, value, min: 1),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _heightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: context.tr('warehouseHeightLabel')),
                  validator: (value) => _validateDouble(context, value, min: 1),
                ),
                const SizedBox(height: AppSpacing.md),
                _SectionTitle(text: context.tr('warehouseRackingData')),
                _TwoColumnNumberFields(
                  left: _DecimalFieldConfig(
                    controller: _rackRowsController,
                    label: context.tr('rackRowsLabel'),
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateInt(context, value, min: 1),
                  ),
                  right: _DecimalFieldConfig(
                    controller: _rackLevelsController,
                    label: context.tr('rackLevelsLabel'),
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateInt(context, value, min: 1),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _TwoColumnNumberFields(
                  left: _DecimalFieldConfig(
                    controller: _rackLengthController,
                    label: context.tr('rackLengthLabel'),
                    validator: (value) => _validateDouble(context, value, min: 0.1),
                  ),
                  right: _DecimalFieldConfig(
                    controller: _rackWidthController,
                    label: context.tr('rackWidthLabel'),
                    validator: (value) => _validateDouble(context, value, min: 0.1),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _aisleWidthController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: context.tr('aisleWidthLabel')),
                  validator: (value) => _validateDouble(context, value, min: 0.5),
                ),
                const SizedBox(height: AppSpacing.md),
                _SectionTitle(text: context.tr('warehouseZonesData')),
                TextFormField(
                  controller: _zonesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: context.tr('zonesInputLabel'),
                    hintText: context.tr('zonesInputHint'),
                  ),
                  validator: (value) {
                    final zones = _parseZoneNames(value ?? '');
                    if (zones.isEmpty) {
                      return context.tr('zonesInputInvalid');
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.tr(widget.submitKey)),
        ),
      ],
    );
  }

  String? _validateInt(
    BuildContext context,
    String? value, {
    required int min,
  }) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < min) {
      return context.tr('invalidNumber');
    }
    return null;
  }

  String? _validateDouble(
    BuildContext context,
    String? value, {
    required double min,
  }) {
    final parsed = _parseDouble(value ?? '');
    if (parsed == null || parsed < min) {
      return context.tr('invalidNumber');
    }
    return null;
  }

  double? _parseDouble(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  List<String> _parseZoneNames(String raw) {
    return raw
        .split(RegExp(r'[,;\n]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final input = NewWarehouseInput(
      name: _nameController.text.trim(),
      location: _locationController.text.trim(),
      status: _status,
      description: _descriptionController.text.trim(),
      lengthM: _parseDouble(_lengthController.text)!,
      widthM: _parseDouble(_widthController.text)!,
      heightM: _parseDouble(_heightController.text)!,
      rackRowCount: int.parse(_rackRowsController.text.trim()),
      rackLengthM: _parseDouble(_rackLengthController.text)!,
      rackWidthM: _parseDouble(_rackWidthController.text)!,
      rackLevels: int.parse(_rackLevelsController.text.trim()),
      aisleWidthM: _parseDouble(_aisleWidthController.text)!,
      zoneNames: _parseZoneNames(_zonesController.text),
    );

    Navigator.of(context).pop(input);
  }

  String _doubleToText(double value) {
    final isInt = value % 1 == 0;
    return isInt ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _TwoColumnNumberFields extends StatelessWidget {
  const _TwoColumnNumberFields({
    required this.left,
    required this.right,
  });

  final _DecimalFieldConfig left;
  final _DecimalFieldConfig right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _DecimalTextField(config: left)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _DecimalTextField(config: right)),
      ],
    );
  }
}

class _DecimalTextField extends StatelessWidget {
  const _DecimalTextField({required this.config});

  final _DecimalFieldConfig config;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: config.controller,
      keyboardType:
          config.keyboardType ?? const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: config.label),
      validator: config.validator,
    );
  }
}

class _DecimalFieldConfig {
  const _DecimalFieldConfig({
    required this.controller,
    required this.label,
    required this.validator,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
}
