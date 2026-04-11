from datetime import datetime

from .models import WarehouseEntity


def build_generated_model(
    warehouse: WarehouseEntity,
    zone_names: list[str],
) -> dict:
    shelf_columns = max(
        1,
        int(warehouse.length_m // (warehouse.rack_length_m + warehouse.aisle_width_m)),
    )
    shelf_rows = max(1, warehouse.rack_row_count)
    shelf_levels = max(1, warehouse.rack_levels)

    normalized_zones = [name.strip() for name in zone_names if name.strip()]
    if not normalized_zones:
        normalized_zones = ["Zone 1"]

    zone_height = 1 / len(normalized_zones)
    zone_payload = []
    for index, name in enumerate(normalized_zones):
        top = round(index * zone_height, 4)
        height = round(zone_height, 4)
        zone_payload.append(
            {
                "name": name,
                "x": 0.02,
                "y": min(0.95, top + 0.02),
                "w": 0.96,
                "h": max(0.04, min(0.95, height - 0.03)),
            }
        )

    return {
        "generated_at": datetime.utcnow().isoformat(),
        "warehouse_length_m": warehouse.length_m,
        "warehouse_width_m": warehouse.width_m,
        "warehouse_height_m": warehouse.height_m,
        "shelf_rows": shelf_rows,
        "shelf_columns": shelf_columns,
        "shelf_levels": shelf_levels,
        "zones": zone_payload,
    }
