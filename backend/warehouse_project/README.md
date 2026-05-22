# Warehouse Analytics API

Warehouse intelligence backend built with:

- FastAPI
- SQLite
- Pandas
- NumPy

Features:

- Storage utilization analytics
- ABC analysis
- Heatmap generation
- Smart relocation recommendations
- REST API endpoints

Endpoints:

/analytics
/heatmap
/critical-locations

In this repository the API is mounted under:

/warehouse-analytics-api/analytics
/warehouse-analytics-api/heatmap
/warehouse-analytics-api/critical-locations

Run:

uvicorn warehouse_api:app --reload
