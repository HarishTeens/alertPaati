package com.example.alertpaati

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInference.LlmInferenceOptions as LlmOptions

/**
 * On-device fraud detection powered by Gemma via MediaPipe LLM Inference
 * (com.google.mediapipe:tasks-genai).
 *
 * ── No .task file needed ──────────────────────────────────────────────────
 * LlmInference.Options.setModelPath() accepts a raw .bin model file directly.
 * A .task bundle is the optional packaging format; the raw binary works fine.
 *
 * ── Model setup ───────────────────────────────────────────────────────────
 * 1. Accept terms and download a model from HuggingFace, e.g.:
 *      https://huggingface.co/google/gemma-3-1b-it-litert-preview
 *    Pick the CPU int8 .bin variant (~1.3 GB, best for most devices).
 * 2. Or use the in-app Download button — it fetches and saves automatically.
 * 3. Call [loadModel] with the saved path.
 *
 * ── Fraud prompt design ───────────────────────────────────────────────────
 * Gemma is prompted as a call-fraud classifier. It returns a JSON payload
 * that [parseGemmaResponse] converts into a Map forwarded to Flutter.
 */
class FraudEngineManager(private val context: Context) {

    companion object {
        private const val TAG = "FraudEngine"

        /**
         * Default path written by the user after pushing the model file.
         * Adjust to the actual filename downloaded from Kaggle.
         */
        private const val DEFAULT_MODEL_PATH =
            "/data/local/tmp/gemma-4-1b-it-cpu-int8.bin"

        private const val MAX_TOKENS = 512

        private val FRAUD_SYSTEM_PROMPT = """
            You are KAVACH, an AI fraud-detection engine embedded in a phone call app.
            Analyze the following call transcript and respond ONLY with valid JSON —
            no extra text, no markdown, no explanation outside the JSON object.

            Required schema:
            {
              "score": <float 0.0 to 1.0>,
              "level": <"safe" | "suspicious" | "danger">,
              "explanation": <one-sentence plain-text summary>,
              "redFlags": [<up to 5 short flag strings>]
            }

            Scoring:
              0.00–0.29 → "safe"
              0.30–0.59 → "suspicious"
              0.60–1.00 → "danger"

            Red flags to detect:
            - Urgency / pressure tactics ("act now", "only today", "hurry")
            - Requests for OTP, bank PIN, Aadhaar, CVV, passwords, account numbers
            - Impersonation of government, police, CBI, income tax, RBI, tech-support
            - Prize / lottery / KBC winner scams
            - Threats of arrest, SIM block, or legal action
            - Gift card, wire transfer, crypto, or Western Union requests
            - Unsolicited "refund" or "fee waiver" offers requiring payment

            Transcript:
        """.trimIndent()
    }

    private var llm: LlmInference? = null

    val isLoaded: Boolean get() = llm != null

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Load a Gemma 4 model from [modelPath] (raw LiteRT .tflite file).
     *
     * Blocks the calling thread for a few seconds — always call on a
     * background dispatcher (Dispatchers.IO).
     *
     * @param modelPath Absolute path to the .tflite model on the device.
     * @param useGpu    Set true when the GPU model variant was downloaded.
     */
    fun loadModel(
        modelPath: String = DEFAULT_MODEL_PATH,
        useGpu: Boolean = false,
    ) {
        Log.d(TAG, "Loading Gemma 4 from $modelPath (gpu=$useGpu)")

        val backend = if (useGpu) LlmInference.Backend.GPU else LlmInference.Backend.CPU
        val options = LlmOptions.builder()
            .setModelPath(modelPath)
            .setMaxTokens(MAX_TOKENS)
            .setMaxTopK(40)
            .setPreferredBackend(backend)
            .build()

        llm?.close()
        llm = LlmInference.createFromOptions(context, options)
        Log.d(TAG, "Model loaded ✓")
    }

    /**
     * Analyze [transcript] for fraud signals using Gemma 4.
     *
     * @return Map with keys: score, level, explanation, redFlags.
     *         Falls back to a keyword heuristic if the model isn't loaded.
     */
    fun analyzeTranscript(transcript: String): Map<String, Any> {
        return if (llm != null) {
            analyzeWithGemma(transcript)
        } else {
            Log.w(TAG, "Model not loaded — heuristic fallback")
            heuristicAnalysis(transcript)
        }
    }

    /**
     * Streaming variant — calls [onToken] for each generated token then
     * returns the assembled map when done.
     * Useful for showing a "thinking…" indicator in the debrief UI.
     */
    fun analyzeTranscriptStreaming(
        transcript: String,
        onToken: (partial: String) -> Unit,
    ): Map<String, Any> {
        val engine = llm ?: return heuristicAnalysis(transcript)
        val prompt = buildPrompt(transcript)
        val buffer = StringBuilder()

        try {
            // MediaPipe generateResponseAsync fires the listener for each partial
            // result and a final call with done=true. Use a CountDownLatch to
            // block until generation completes on the background thread.
            val latch = java.util.concurrent.CountDownLatch(1)
            engine.generateResponseAsync(prompt) { partialResult, done ->
                if (!partialResult.isNullOrEmpty()) {
                    buffer.append(partialResult)
                    onToken(buffer.toString())
                }
                if (done == true) latch.countDown()
            }
            latch.await(30, java.util.concurrent.TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.e(TAG, "Streaming inference failed", e)
            return errorResult(e.message ?: "Streaming error")
        }

        return parseGemmaResponse(buffer.toString())
    }

    fun close() {
        llm?.close()
        llm = null
    }

    // ── Gemma inference ───────────────────────────────────────────────────────

    private fun analyzeWithGemma(transcript: String): Map<String, Any> {
        return try {
            val prompt = buildPrompt(transcript)
            val raw = llm!!.generateResponse(prompt)
            Log.d(TAG, "Gemma response: $raw")
            parseGemmaResponse(raw)
        } catch (e: Exception) {
            Log.e(TAG, "Gemma inference failed", e)
            errorResult(e.message ?: "Inference error")
        }
    }

    /**
     * Gemma 4 instruction-tuned models use the `<start_of_turn>` format:
     *
     *   <start_of_turn>user
     *   {system prompt + transcript}
     *   <end_of_turn>
     *   <start_of_turn>model
     */
    private fun buildPrompt(transcript: String): String = buildString {
        append("<start_of_turn>user\n")
        append(FRAUD_SYSTEM_PROMPT)
        append("\n\n")
        append(transcript.take(4096)) // guard against runaway transcripts
        append("\n<end_of_turn>\n")
        append("<start_of_turn>model\n")
    }

    /**
     * Robustly extracts the first complete JSON object from Gemma's output.
     * The model sometimes emits markdown code fences or preamble text.
     */
    private fun parseGemmaResponse(raw: String): Map<String, Any> {
        val jsonStr = extractJson(raw) ?: run {
            Log.w(TAG, "No JSON found in: $raw")
            return errorResult("No JSON in model response")
        }
        return try {
            val obj = org.json.JSONObject(jsonStr)
            val flags = mutableListOf<String>()
            val arr = obj.optJSONArray("redFlags")
            if (arr != null) {
                for (i in 0 until arr.length()) flags.add(arr.getString(i))
            }
            val score = obj.optDouble("score", 0.0).coerceIn(0.0, 1.0)
            val level = when {
                score >= 0.60 -> "danger"
                score >= 0.30 -> "suspicious"
                else -> "safe"
            }.let { obj.optString("level", it) } // prefer model's own label
            mapOf(
                "score"       to score,
                "level"       to level,
                "explanation" to obj.optString("explanation", ""),
                "redFlags"    to flags,
            )
        } catch (e: Exception) {
            Log.e(TAG, "JSON parse error for: $jsonStr", e)
            errorResult("Parse error: ${e.message}")
        }
    }

    private fun extractJson(text: String): String? {
        // Strip markdown fences if present: ```json ... ```
        val stripped = text
            .replace(Regex("```json\\s*", RegexOption.IGNORE_CASE), "")
            .replace(Regex("```\\s*"), "")
            .trim()

        val start = stripped.indexOf('{')
        val end = stripped.lastIndexOf('}')
        if (start == -1 || end == -1 || end <= start) return null
        return stripped.substring(start, end + 1)
    }

    // ── Keyword heuristic (model-not-loaded fallback) ─────────────────────────

    private val DANGER_KEYWORDS = listOf(
        "otp", "one time password", "cvv", "pin", "bank account", "aadhaar",
        "arrested", "police", "cbi", "income tax", "lottery", "prize", "won",
        "gift card", "wire transfer", "bitcoin", "crypto", "urgent", "immediately",
        "limited time", "act now", "verify your", "suspend", "blocked", "rbi",
        "sim block", "legal notice", "court summons",
    )

    private val SUSPICIOUS_KEYWORDS = listOf(
        "offer", "discount", "free", "congratulations", "selected",
        "customer care", "refund", "claim", "process fee", "kbc",
    )

    private fun heuristicAnalysis(transcript: String): Map<String, Any> {
        val lower = transcript.lowercase()
        val dangerHits = DANGER_KEYWORDS.filter { lower.contains(it) }
        val suspiciousHits = SUSPICIOUS_KEYWORDS.filter { lower.contains(it) }

        val (score, level, explanation) = when {
            dangerHits.size >= 2 -> Triple(
                0.85, "danger",
                "Multiple high-risk fraud indicators detected."
            )
            dangerHits.size == 1 -> Triple(
                0.65, "danger",
                "Fraud keyword detected: \"${dangerHits.first()}\"."
            )
            suspiciousHits.size >= 2 -> Triple(
                0.45, "suspicious",
                "Multiple suspicious patterns suggest a potential scam."
            )
            suspiciousHits.size == 1 -> Triple(
                0.25, "safe",
                "Minor suspicious keyword; call appears safe overall."
            )
            else -> Triple(0.05, "safe", "No fraud indicators detected.")
        }

        return mapOf(
            "score"       to score,
            "level"       to level,
            "explanation" to explanation,
            "redFlags"    to (dangerHits + suspiciousHits).take(5),
        )
    }

    private fun errorResult(msg: String): Map<String, Any> = mapOf(
        "score"       to 0.0,
        "level"       to "safe",
        "explanation" to "Analysis unavailable: $msg",
        "redFlags"    to emptyList<String>(),
    )
}
