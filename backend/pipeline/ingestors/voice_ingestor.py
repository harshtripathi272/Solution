import logging
from google.cloud import speech_v2
from pipeline.core.pubsub import broker

logger = logging.getLogger(__name__)

class VoiceStreamingIngestor:
    """
    Real-time Interactive Voice Response (IVR) ingestion.
    Allows field workers with basic feature phones to call in, speak their report 
    (in Hindi, Chhattisgarhi, or English), and the system utilizes Google's Universal 
    Speech Model (Chirp) for transcription to bypass language and literacy barriers.
    """
    def __init__(self):
        try:
            self.client = speech_v2.SpeechClient()
            self.is_configured = True
        except Exception as e:
            logger.warning(f"[INGESTOR] Could not initialize google-cloud-speech. Running mock mode. Error: {e}")
            self.is_configured = False

    async def transcribe_audio_stream(self, audio_content: bytes, project_id: str = "sevasetu-prod"):
        """
        Synchronous wrapper over Cloud Speech V2 API for processing chunks of 
        telephony/app audio.
        """
        if not self.is_configured:
            logger.info("[MOCK STT] Transcribing incoming audio snippet using Chirp simulation...")
            return "medical emergency main chauraha par, ambulance bhej do jaldi."

        # Configure Google's Chirp model for Indian dialect handling
        # including Chhattisgarhi and standard Hindi.
        config = speech_v2.RecognitionConfig(
            auto_decoding_config=speech_v2.AutoDetectDecodingConfig(),
            language_codes=["hi-IN", "en-US", "hne"], # 'hne' is Chhattisgarhi
            model="chirp",
        )

        request = speech_v2.RecognizeRequest(
            recognizer=f"projects/{project_id}/locations/global/recognizers/_",
            config=config,
            content=audio_content,
        )

        try:
            response = self.client.recognize(request=request)
            
            # Extract the transcript from the highest confidence alternative
            full_transcript = []
            for result in response.results:
                best_alternative = result.alternatives[0]
                full_transcript.append(best_alternative.transcript)
                
            final_text = " ".join(full_transcript)
            logger.info(f"[VOICE INGESTION] Chirp STT Result: {final_text}")
            
            # Pass to NLP extraction pipeline 
            # (which handles NER and LLM parsing to convert raw strings into CrisisEvents)
            return final_text
            
        except Exception as e:
            logger.error(f"[INGESTOR] Chirp Voice Transcription Failed: {e}")
            return None

voice_ingestor = VoiceStreamingIngestor()
