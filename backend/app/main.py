import json
import uuid
from datetime import datetime

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from .database import Base, engine, get_db
from .model_generator import build_generated_model
from .models import WarehouseEntity, WarehouseModelEntity, WarehouseZoneEntity
from .schemas import WarehouseCreate, WarehouseModelResponse, WarehouseRead

app = FastAPI(title="Schaeflein LagerView API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    Base.metadata.create_all(bind=engine)


def _to_warehouse_read(entity: WarehouseEntity) -> WarehouseRead:
    model_payload = None
    if entity.generated_model is not None:
        parsed = json.loads(entity.generated_model.model_json)
        parsed["generated_at"] = entity.generated_model.generated_at
        model_payload = parsed

    return WarehouseRead(
        id=entity.id,
        name=entity.name,
        location=entity.location,
        status=entity.status,
        description=entity.description,
        created_at=entity.created_at,
        layout={
            "length_m": entity.length_m,
            "width_m": entity.width_m,
            "height_m": entity.height_m,
            "rack_row_count": entity.rack_row_count,
            "rack_length_m": entity.rack_length_m,
            "rack_width_m": entity.rack_width_m,
            "rack_levels": entity.rack_levels,
            "aisle_width_m": entity.aisle_width_m,
        },
        zones=[{"id": zone.id, "name": zone.name} for zone in entity.zones],
        model=model_payload,
    )


def _apply_payload_to_entity(
    warehouse: WarehouseEntity,
    payload: WarehouseCreate,
) -> None:
    warehouse.name = payload.name.strip()
    warehouse.location = payload.location.strip()
    warehouse.status = payload.status.strip().lower()
    warehouse.description = payload.description.strip()
    warehouse.length_m = payload.length_m
    warehouse.width_m = payload.width_m
    warehouse.height_m = payload.height_m
    warehouse.rack_row_count = payload.rack_row_count
    warehouse.rack_length_m = payload.rack_length_m
    warehouse.rack_width_m = payload.rack_width_m
    warehouse.rack_levels = payload.rack_levels
    warehouse.aisle_width_m = payload.aisle_width_m


def _replace_zones(
    db: Session,
    warehouse: WarehouseEntity,
    zone_names: list[str],
) -> None:
    for existing in list(warehouse.zones):
        db.delete(existing)
    for zone_name in zone_names:
        db.add(
            WarehouseZoneEntity(
                warehouse_id=warehouse.id,
                name=zone_name,
            )
        )


@app.get("/warehouses", response_model=list[WarehouseRead])
def get_warehouses(db: Session = Depends(get_db)) -> list[WarehouseRead]:
    warehouses = db.query(WarehouseEntity).order_by(WarehouseEntity.created_at.desc()).all()
    return [_to_warehouse_read(item) for item in warehouses]


@app.post("/warehouses", response_model=WarehouseRead, status_code=status.HTTP_201_CREATED)
def create_warehouse(payload: WarehouseCreate, db: Session = Depends(get_db)) -> WarehouseRead:
    warehouse = WarehouseEntity(
        id=f"wh-{uuid.uuid4().hex[:12]}",
        name="",
        location="",
        status="online",
        description="",
        length_m=1,
        width_m=1,
        height_m=1,
        rack_row_count=1,
        rack_length_m=1,
        rack_width_m=1,
        rack_levels=1,
        aisle_width_m=1,
    )
    _apply_payload_to_entity(warehouse, payload)
    db.add(warehouse)
    db.flush()

    zone_names = [name.strip() for name in payload.zones if name.strip()]
    if not zone_names:
        zone_names = ["Zone 1"]
    _replace_zones(db, warehouse, zone_names)

    db.commit()
    db.refresh(warehouse)
    return _to_warehouse_read(warehouse)


@app.get("/warehouses/{warehouse_id}", response_model=WarehouseRead)
def get_warehouse(warehouse_id: str, db: Session = Depends(get_db)) -> WarehouseRead:
    warehouse = db.get(WarehouseEntity, warehouse_id)
    if warehouse is None:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    return _to_warehouse_read(warehouse)


@app.put("/warehouses/{warehouse_id}", response_model=WarehouseRead)
def update_warehouse(
    warehouse_id: str,
    payload: WarehouseCreate,
    db: Session = Depends(get_db),
) -> WarehouseRead:
    warehouse = db.get(WarehouseEntity, warehouse_id)
    if warehouse is None:
        raise HTTPException(status_code=404, detail="Warehouse not found.")

    _apply_payload_to_entity(warehouse, payload)
    zone_names = [name.strip() for name in payload.zones if name.strip()]
    if not zone_names:
        zone_names = ["Zone 1"]
    _replace_zones(db, warehouse, zone_names)

    db.commit()
    db.refresh(warehouse)
    return _to_warehouse_read(warehouse)


@app.delete("/warehouses/{warehouse_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_warehouse(warehouse_id: str, db: Session = Depends(get_db)) -> None:
    warehouse = db.get(WarehouseEntity, warehouse_id)
    if warehouse is None:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    db.delete(warehouse)
    db.commit()


@app.post("/warehouses/{warehouse_id}/generate-model", response_model=WarehouseRead)
def generate_model(warehouse_id: str, db: Session = Depends(get_db)) -> WarehouseRead:
    warehouse = db.get(WarehouseEntity, warehouse_id)
    if warehouse is None:
        raise HTTPException(status_code=404, detail="Warehouse not found.")

    zone_names = [zone.name for zone in warehouse.zones]
    model_data = build_generated_model(warehouse, zone_names)

    model_entity = db.get(WarehouseModelEntity, warehouse_id)
    if model_entity is None:
        model_entity = WarehouseModelEntity(
            warehouse_id=warehouse_id,
            generated_at=datetime.utcnow(),
            model_json=json.dumps(model_data),
        )
        db.add(model_entity)
    else:
        model_entity.generated_at = datetime.utcnow()
        model_entity.model_json = json.dumps(model_data)

    db.commit()
    db.refresh(warehouse)
    return _to_warehouse_read(warehouse)


@app.get("/warehouses/{warehouse_id}/model", response_model=WarehouseModelResponse)
def get_generated_model(
    warehouse_id: str,
    db: Session = Depends(get_db),
) -> WarehouseModelResponse:
    warehouse = db.get(WarehouseEntity, warehouse_id)
    if warehouse is None:
        raise HTTPException(status_code=404, detail="Warehouse not found.")

    model_entity = db.get(WarehouseModelEntity, warehouse_id)
    if model_entity is None:
        return WarehouseModelResponse(warehouse_id=warehouse_id, model=None)

    parsed = json.loads(model_entity.model_json)
    parsed["generated_at"] = model_entity.generated_at
    return WarehouseModelResponse(warehouse_id=warehouse_id, model=parsed)
