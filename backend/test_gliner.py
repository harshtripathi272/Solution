import asyncio
from pipeline.processing.extraction_strategy import GLiNERExtractor

def run_test():
    # 1. Initialize our newly built Extractor
    extractor = GLiNERExtractor()
    
    # 2. Provide a tricky sentence that hardcoded keywords would fail on
    sample_text = (
        "Following heavy torrential rains, the primary embankment breached overnight. "
        "Massive inundation has severely affected the agricultural belt of Kusheshwar Asthan, "
        "leaving dozens of families stranded and critical infrastructure destroyed."
    )
    
    print("\n--- Input Text ---")
    print(sample_text)
    
    # 3. Extract the intelligence based on our thresholds
    print("\nExtracting entities through the pipeline threshold logic...")
    result = extractor.extract(sample_text)
    
    print("\n--- RAW GLiNER OUTPUT (Exactly what the AI saw) ---")
    # Now that extract() was called, extractor.model is guaranteed to be loaded
    raw_entities = extractor.model.predict_entities(sample_text, extractor.labels)
    for e in raw_entities:
        print(f"[{e['label']}] '{e['text']}' (Confidence: {e['score']:.2f})")
    
    print("\n--- GLiNER Extraction Output ---")
    print(f"Crisis Type Found : {result.get('need_type')}")
    print(f"Locations Found   : {result.get('places')}")
    print(f"Severity Level    : {result.get('severity')}")
    print(f"Confidence Score  : {result.get('confidence'):.2f}")

if __name__ == "__main__":
    run_test()
