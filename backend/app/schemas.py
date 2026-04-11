from datetime import datetime

from pydantic import BaseModel, Field


class WarehouseCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    location: str = Field(min_length=1, max_length=200)
    status: str = Field(default="online")
    description: str = Field(default="")

    length_m: float = Field(gt=0)
    width_m: float = Field(gt=0)
    height_m: float = Field(gt=0)

    rack_row_count: int = Field(ge=1)
    rack_length_m: float = Field(gt=0)
    rack_width_m: float = Field(gt=0)
    rack_levels: int = Field(ge=1)
    aisle_width_m: float = Field(gt=0)

    zones: list[str] = Field(default_factory=list)


class WarehouseZoneRead(BaseModel):
    id: int
    name: str


class WarehouseLayoutRead(BaseModel):
    length_m: float
    width_m: float
    height_m: float
    rack_row_count: int
    rack_length_m: float
    rack_width_m: float
    rack_levels: int
    aisle_width_m: float


class GeneratedModelZone(BaseModel):
    name: str
    x: float
    y: float
    w: float
    h: float


class GeneratedWarehouseModel(BaseModel):
    generated_at: datetime
    warehouse_length_m: float
    warehouse_width_m: float
    warehouse_height_m: float
    shelf_rows: int
    shelf_columns: int
    shelf_levels: int
    zones: list[GeneratedModelZone]


class WarehouseRead(BaseModel):
    id: str
    name: str
    location: str
    status: str
    description: str
    created_at: datetime
    layout: WarehouseLayoutRead
    zones: list[WarehouseZoneRead]
    model: GeneratedWarehouseModel | None = None


class WarehouseModelResponse(BaseModel):
    warehouse_id: str
    model: GeneratedWarehouseModel | None
