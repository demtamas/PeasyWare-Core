# PeasyWare-Core

![PeasyWare Logo](src/Assets/peasyware-logo.svg)

Core architecture of **PeasyWare** — an experimental **Warehouse Management System (WMS)** built to model real warehouse operations including inbound receiving, inventory management, putaway, and outbound logistics.

PeasyWare explores how real warehouse systems operate by implementing simplified versions of concepts used in enterprise platforms such as **SAP EWM**, **Manhattan WMS**, and **Blue Yonder**.

---

# Overview

**PeasyWare** is a learning and architecture project designed to model real warehouse operations in software.

The project is built using:

- **C# (.NET)**
- **SQL Server**
- **Layered / Clean Architecture**

The system models how inventory moves through a warehouse and how software coordinates those movements.

Core warehouse concepts implemented include:

- inbound receiving  
- SSCC / inventory unit tracking  
- warehouse locations and bins  
- putaway strategies  
- warehouse task generation  
- outbound inventory availability  

---

# Architecture

PeasyWare follows a layered architecture inspired by Clean Architecture and real-world warehouse systems.

```
User Interfaces
   CLI (RF-style terminal)
   Desktop Application
        │
        ▼
Application Layer
   Use Cases / Flows
   Services
   DTOs
        │
        ▼
Domain Layer
   Core Warehouse Logic
   Inventory Units
   Warehouse Tasks
   Locations / Bins
        │
        ▼
Infrastructure Layer
   SQL Repositories
   Configuration
   External Integrations
        │
        ▼
Database
   SQL Server
   Warehouses / Inventory
   Deliveries / Tasks
```

---

# Warehouse Flow Model

A simplified representation of how inventory moves through the system.

```
Inbound Delivery
      │
      ▼
Receive SSCC
      │
      ▼
Inventory Unit Created
      │
      ▼
Putaway Task Generated
      │
      ▼
Inventory Moved To Location
      │
      ▼
Stock Available For Outbound
```

These movements eventually translate into **Warehouse Tasks**, representing physical work performed in the warehouse such as:

- moving a pallet  
- picking inventory  
- replenishing storage locations  

---

# Quick Start

## 1 — Clone the repository

```
git clone https://github.com/demtamas/PeasyWare-Core.git
```

---

## 2 — Initialize the database

Development helper scripts are currently provided to quickly create a working development environment.

Run the following scripts:

```
Database/DEV/DEV_AllInOneGo.sql
Database/DEV/DEV_WIP.sql
Database/DEV/DEV_Test_Data_Samples.sql
```

Running these scripts will:

- create the **PW_Core_DEV** database  
- create all required schemas and tables  
- load sample development data  

These scripts currently support **Microsoft SQL Server**.

In future versions they will be replaced by consolidated migration scripts located in:

```
Database/Scripts
```

---

## 3 — Configure the connection string

Before building the project, update the database connection string.

Edit the file:

```
src/PeasyWare.Infrastructure/Bootstrap/BootstrapLoader
```

Adjust the connection string so it points to your SQL Server instance.

Example:

```
Server=localhost;
Database=PeasyWare_DEV;
Trusted_Connection=True;
```

---

## 4 — Build the project

From the repository root:

```
dotnet build
```

---

## 5 — Run the CLI

The CLI simulates a **warehouse RF terminal**, similar to handheld scanners used on warehouse shop floors.

Run the application by either

```
dotnet run --project src/PeasyWare.CLI or
dotnet run --project src/PeasyWare.Desktop

Initial credentials are admin / admin0, you'll be propmpted to update to a password at least 8 characters long and containing letter, capital and number at least one of each.

```

---

# Project Status

PeasyWare is an **experimental architecture project** exploring the design of warehouse management systems.

The goal of the project is to model the core concepts behind real WMS platforms while demonstrating an understanding of both:

- the **under-the-hood system architecture** that drives warehouse software  
- the **physical realities of warehouse shop-floor operations**

Rather than focusing only on code, PeasyWare attempts to represent how inventory actually moves through a warehouse and how software coordinates those movements.

The project explores concepts such as:

- inbound receiving and handling units (SSCC)
- inventory unit lifecycle
- warehouse locations and bins
- putaway logic and storage strategies
- warehouse task generation
- inventory availability for outbound operations

PeasyWare is intentionally developed as a **learning and architecture exercise**, where the domain model and operational workflows evolve as the system grows.

---

# Development Status

### Currently Implemented

- database schema foundation
- user and session management  
- inbound delivery structures  
- SSCC / inventory unit model  
- warehouse locations and bins  
- initial putaway logic  
- CLI terminal foundation  

### In Progress

- inbound receiving workflows  
- warehouse task generation  
- inventory movement logic  
- CLI warehouse process flows  

### Planned

- GTIN resolver
- outbound picking   
- replenishment logic  
- warehouse task orchestration  
- API layer  
- improved desktop interface  

---

# Documentation

More detailed technical documentation will be available in the **docs** folder.

```
docs/
   architecture.md
   domain-model.md
   warehouse-flows.md
```

These documents describe the internal design of PeasyWare in greater depth.

---

# Inspiration

PeasyWare is inspired by real warehouse management systems such as:

- SAP EWM  
- Manhattan WMS  
- Blue Yonder  

combined with real warehouse shop-floor experience across facilities of different sizes and operational models handling a wide variety of merchandise.

---

# License

MIT License