# 🏗️ SevaSetu: Project Structure & Core Concepts

SevaSetu is a **Real-Time Community Crisis Monitoring System** designed to bridge the gap between affected communities, NGOWorkers, and Coordinators. It leverages automated ingestion, AI-driven processing, and role-based mobile interfaces to provide a cohesive disaster response platform.

---

## 📁 Root Directory
Global configuration, documentation, and metadata.

| File | Concept | Idea |
| :--- | :--- | :--- |
| `INDEX.md` | **Master Index** | The entry point for developers to find specific documentation and quick-start guides. |
| `SYSTEM_OVERVIEW.md` | **High-Level Architecture** | Visualizes how data flows from sources (RSS, Social) to the Flutter UI. |
| `README.md` | **Project Entry** | Overview of the mission, installation, and core features. |
| `pubspec.yaml` | **Flutter Identity** | Defines the Flutter app dependencies (Firebase, Hive, Animate). |
| `firebase.json` | **Cloud Config** | Configuration for Firebase Hosting, Functions, and Firestore rules. |
| `.env` | **Environment Secrets** | Stores API keys, database URLs, and feature flags for the backend. |

---

## 🐍 Backend Engine (`/backend`)
A FastAPI-based resilient pipeline for crisis intelligence.

### ⚙️ Core Infrastructure (`/pipeline/core`)
| File | Concept | Idea |
| :--- | :--- | :--- |
| `schemas.py` | **Data Contracts** | Defines `UnifiedIngestionEvent` and `CrisisEvent`. Ensures the entire system speaks the same language. |
| `pubsub.py` | **Event Bus** | An internal broker that allows ingestors to publish events without knowing who processes them. |

### 📥 Data Ingestors (`/pipeline/ingestors`)
| File | Concept | Idea |
| :--- | :--- | :--- |
| `global_rss_monitor.py` | **Contextual Ingestion** | Monitors Google News RSS for local crisis keywords (Gram Panchayat, flood breach). |
| `mastodon_ingestor.py` | **Social Pulse** | Scrapes decentralized social media for real-time community reports using hashtags. |
| `manager.py` | **Ingestion Orchestration** | The central registry that starts, stops, and schedules all ingestor workers. |

### 🧠 Intelligence Layer (`/pipeline/processing`)
| File | Concept | Idea |
| :--- | :--- | :--- |
| `extraction_strategy.py` | **Source Trust** | Defines how much we trust each source (e.g., NGO reports have higher confidence than Social Media). |
| `unified_extractor.py` | **Information Refinement** | Extracts locations and entities (NER) from raw text descriptions. |
| `multimodal_preprocessor.py` | **Visual Intelligence** | Uses AI to analyze images/videos from NGO reports to estimate destruction and population affected. |

### 🛂 Orchestrators (`/pipeline/orchestrators`)
| File | Concept | Idea |
| :--- | :--- | :--- |
| `unified.py` | **Event Unification** | The "brain" of the pipeline. It takes raw inputs, geocodes them, hashes them for deduplication, and stores them in Firestore. |
| `allocation.py` | **Resource Matching** | Logic to match crisis events with available volunteers based on proximity and skills. |

---

## 📱 Flutter Mobile App (`/lib`)
A multi-role mobile application built with Provider and Hive.

### 🏗️ State & Config
| File | Concept | Idea |
| :--- | :--- | :--- |
| `main.dart` | **Bootstrap** | Initializes Firebase, Hive (local cache), and starts the app with Global State. |
| `app.dart` | **Navigation Shell** | Handles Role-Based UI. Switches the dashboard based on whether you are a Coordinator, Volunteer, or NGO Worker. |
| `providers/app_state.dart` | **Reactive State** | The central store for user profile, current role, and active navigation. |

### 🖼️ Screens & Components
| Directory/File | Concept | Idea |
| :--- | :--- | :--- |
| `screens/auth_wrapper.dart` | **Session Guard** | Listens to Firebase Auth to decide between showing Login or the Dashboard. |
| `screens/coordinator/` | **Control Center** | Screens like `HeatmapScreen` for high-level monitoring and `SDGDashboard` for impact reporting. |
| `screens/ngo_worker/` | **Field Reporting** | Focused on `ReportSubmissionScreen`—where evidence (photos/GPS) is gathered. |
| `screens/volunteer/` | **Action Feed** | `TaskFeedScreen` shows nearby crises that need immediate manpower. |
| `widgets/crisis_alert_card.dart` | **Atomic UI** | A reusable card that displays crisis intensity using color-coded levels. |

---

## 🧪 Testing & Validation (`/test`)
| File | Concept | Idea |
| :--- | :--- | :--- |
| `simulate_ngo_flow.py` | **Loop Testing** | Mocks an injection of data from an NGO ingestor to verify it reaches Firestore. |
| `test_unified_pipeline.py` | **Logic Verification** | Unit tests for deduplication, geocoding, and data normalization. |
| `widget_test.dart` | **UI Verification** | Basic Flutter tests to ensure the app doesn't crash on boot. |

---

## 🛠️ Concepts & Key Ideas

1.  **Temporal-Spatial Deduplication**: The system uses a 5-character geohash (~5km grid) and event dates to prevent "Alert Fatigue"—ensuring 10 reports of the same flood aren't treated as 10 separate disasters.
2.  **Privacy-By-Design Location Tracking**: Volunteer locations are stored temporarily in Redis with a 2-hour TTL. They are never written to Firestore, protecting user privacy while enabling real-time response.
3.  **Tiered Source Verification**:
    - **Tier 1 (Official)**: NDMA, Govt Reports.
    - **Tier 2 (Verified Personnel)**: NGO Workers reporting from the ground.
    - **Tier 3 (Contextual)**: Social media and news RSS.
4.  **Multimodal Awareness**: The backend doesn't just read text; it uses Vision models to look at photos of "Bund Breaches" to verify the severity reported by users.
