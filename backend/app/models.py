from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class WarehouseEntity(Base):
    __tablename__ = "warehouses"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    location: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(String(40), nullable=False, default="online")
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")

    length_m: Mapped[float] = mapped_column(Float, nullable=False)
    width_m: Mapped[float] = mapped_column(Float, nullable=False)
    height_m: Mapped[float] = mapped_column(Float, nullable=False)

    rack_row_count: Mapped[int] = mapped_column(Integer, nullable=False)
    rack_length_m: Mapped[float] = mapped_column(Float, nullable=False)
    rack_width_m: Mapped[float] = mapped_column(Float, nullable=False)
    rack_levels: Mapped[int] = mapped_column(Integer, nullable=False)
    aisle_width_m: Mapped[float] = mapped_column(Float, nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    zones: Mapped[list["WarehouseZoneEntity"]] = relationship(
        "WarehouseZoneEntity",
        cascade="all, delete-orphan",
        back_populates="warehouse",
    )
    generated_model: Mapped["WarehouseModelEntity | None"] = relationship(
        "WarehouseModelEntity",
        cascade="all, delete-orphan",
        uselist=False,
        back_populates="warehouse",
    )


class WarehouseZoneEntity(Base):
    __tablename__ = "warehouse_zones"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    warehouse_id: Mapped[str] = mapped_column(
        ForeignKey("warehouses.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)

    warehouse: Mapped[WarehouseEntity] = relationship("WarehouseEntity", back_populates="zones")


class WarehouseModelEntity(Base):
    __tablename__ = "warehouse_models"

    warehouse_id: Mapped[str] = mapped_column(
        ForeignKey("warehouses.id", ondelete="CASCADE"),
        primary_key=True,
    )
    generated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    model_json: Mapped[str] = mapped_column(Text, nullable=False)

    warehouse: Mapped[WarehouseEntity] = relationship(
        "WarehouseEntity",
        back_populates="generated_model",
    )
