# Implementation Roadmap: Document Intelligence Stream

This document outlines the phase-wise integration of PDF and publication data from NGOs into the SevaSetu real-time crisis response pipeline.

---

## Phase 1: Foundation & Schema Evolution
**Goal**: Prepare the core architecture to treat documents as "Contextual Baselines."

1.  **Schema Updates (`schemas.py`)**:
    *   Add `need_temporality` (Enum: `CHRONIC`, `ACUTE`).
    *   Add `DocumentMetadata` (source NGO, PDF URL, publication date, SHA-256 hash).
    *   Add `activation_window` to `CrisisEvent` for predictive tasks.
2.  **Storage Extension**:
    *   **BigQuery**: Create a partitioned `document_events` table.
    *   **Firestore**: Add a `document_registry` collection to track SHA-256 hashes for deduplication.
3.  **Pub/Sub Bridge**:
    *   Create a new topic: `document-intelligence-raw`.

## Phase 2: Ingestion & Extraction Engine
**Goal**: Convert raw PDFs into structured JSON intelligence.

1.  **Zero-Disk Ingestor**:
    *   Implement a Cloud Function that streams PDF URLs from Scrapy output into `io.BytesIO`.
2.  **Mistral OCR Integration**:
    *   Primary path for scanned/handwritten documents to preserve table structures in markdown.
3.  **Gemini Flash Reasoning**:
    *   Secondary/Optimization path for smaller PDFs.
    *   Extraction of: Locations, infrastructure gaps, seasonal urgency, and vulnerable groups.
4.  **Normalization Adapter**:
    *   Map OCR/LLM output to the standard `UnifiedIngestionEvent` with `source_tier=2`.

## Phase 3: Aggregation & Fusion Logic
**Goal**: Converge real-time and document data streams.

1.  **Temporal Clustering**:
    *   Update `aggregation_layer.py` to recognize chronic vs. acute signals.
    *   Implement weighting: **Chronic (0.3)** and **Acute (0.7)**.
2.  **Ground Truth Validation Loop**:
    *   Synchronous lookup in `aggregation_layer.py`: Resolve real-time signals against historical document ground truth to boost/suppress confidence scores.
3.  **Redis TTL Logic**:
    *   Acute needs: 24-hour TTL.
    *   Chronic needs: 30-day TTL.

## Phase 4: Predictive Mobilization
**Goal**: Transition from reactive to proactive volunteer coordination.

1.  **Rolling Window Analyzer**:
    *   Analyze 90-day document windows to detect recurring seasonal patterns (e.g., Bundelkhand water stress).
2.  **Predictive Task Generator**:
    *   Publish `predicted_tasks` to the `preposition-tasks` Pub/Sub topic.
3.  **Engine Dispatch**:
    *   Update `AllocationEngine` to prioritize predictive tasks for pre-positioning volunteers.

## Phase 5: Monitoring & Impact Analytics
**Goal**: Dashboarding and proof of recovery.

1.  **Recovery Tracking**:
    *   SQL views in BigQuery comparing village recovery times before/after document-validated coordination.
2.  **Dashboard Integration**:
    *   Badge differentiation in the UI (Red for Critical/Acute, Amber for Chronic).

---

## 2. Infrastructure Requirements
- **Google Cloud Functions**: For the ingestion scheduler.
- **Mistral OCR API**: For high-trust table extraction.
- **Google Gemini 2.0 Flash**: For structured reasoning.
- **Firestore**: For state tracking and validation ground truth.
