import 'package:flutter/material.dart';

import '../core/colombia.dart';
import '../core/theme.dart';

/// Lista desplegable con buscador (para departamentos y municipios, que son muchos).
Future<String?> showSearchPicker(BuildContext context, {required String title, required List<String> options, String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SearchPicker(title: title, options: options, selected: selected),
  );
}

class _SearchPicker extends StatefulWidget {
  const _SearchPicker({required this.title, required this.options, this.selected});
  final String title;
  final List<String> options;
  final String? selected;
  @override
  State<_SearchPicker> createState() => _SearchPickerState();
}

/// Búsqueda sin tildes ni mayúsculas: "bolivar" encuentra "Bolívar".
String _fold(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}

class _SearchPickerState extends State<_SearchPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _fold(_q.trim());
    final items = q.isEmpty ? widget.options : widget.options.where((o) => _fold(o).contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: widget.options.length > 12,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: 'Buscar…',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Color(0xFFE6E9DE),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Sin resultados', style: TextStyle(color: NetJobColors.muted)))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final o = items[i];
                      final sel = o == widget.selected;
                      return ListTile(
                        title: Text(o, style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? NetJobColors.primary : NetJobColors.ink)),
                        trailing: sel ? const Icon(Icons.check_rounded, color: NetJobColors.primary) : null,
                        onTap: () => Navigator.pop(context, o),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Dos selectores enlazados: Departamento → Municipio (datos DIVIPOLA del DANE).
class DepartmentCityPicker extends StatelessWidget {
  const DepartmentCityPicker({
    super.key,
    required this.department,
    required this.city,
    required this.onChanged,
    this.decorate,
    this.showErrors = false,
  });
  final String? department;
  final String? city;
  final void Function(String? department, String? city) onChanged;

  /// Envuelve cada selector (por ejemplo, en un campo "de vidrio").
  final Widget Function(Widget child)? decorate;
  final bool showErrors;

  @override
  Widget build(BuildContext context) {
    final wrap = decorate ?? (w) => w;
    Widget field(String label, String? value, IconData icon, VoidCallback? onTap, String? error) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            wrap(
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 19),
                  child: Row(children: [
                    Icon(icon, color: const Color(0xFF878E87)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          value ?? label,
                          key: ValueKey(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: value == null ? (onTap == null ? const Color(0xFFB3B9B1) : const Color(0xFF878E87)) : NetJobColors.ink,
                            fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more_rounded, color: onTap == null ? const Color(0xFFB3B9B1) : const Color(0xFF878E87)),
                  ]),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 6),
                child: Text(error, style: const TextStyle(color: Color(0xFFC8452F), fontSize: 12)),
              ),
          ],
        );

    return Column(children: [
      field(
        'Departamento',
        department,
        Icons.map_outlined,
        () async {
          final d = await showSearchPicker(context, title: 'Departamento', options: colombiaDepartamentos, selected: department);
          if (d != null && d != department) onChanged(d, null);
        },
        showErrors && department == null ? 'Elige el departamento' : null,
      ),
      const SizedBox(height: 14),
      field(
        department == null ? 'Municipio (elige primero el departamento)' : 'Municipio',
        city,
        Icons.location_city_outlined,
        department == null
            ? null
            : () async {
                final options = [for (final m in colombiaMunicipios[department]!) m.$1];
                if (options.length == 1) return onChanged(department, options.first);
                final c = await showSearchPicker(context, title: 'Municipio de $department', options: options, selected: city);
                if (c != null) onChanged(department, c);
              },
        showErrors && department != null && city == null ? 'Elige el municipio' : null,
      ),
    ]);
  }
}
