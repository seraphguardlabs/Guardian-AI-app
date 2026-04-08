package com.example.guardian_ai_gemma4

import android.graphics.Bitmap
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

object GemmaLiteEngine {
    private var modelPath: String? = null
    private var engine: Engine? = null
    private var conversation: Conversation? = null

    @Synchronized
    fun initialize(path: String) {
        if (modelPath == path && engine != null && conversation != null) {
            return
        }

        closeResources()

        val config = EngineConfig(
            modelPath = path,
            backend = Backend.CPU(),
            visionBackend = Backend.CPU(),
        )

        val createdEngine = Engine(config)
        createdEngine.initialize()
        val createdConversation = createdEngine.createConversation()

        engine = createdEngine
        conversation = createdConversation
        modelPath = path
    }

    @Synchronized
    fun score(bitmap: Bitmap): RiskSnapshot {
        if (modelPath.isNullOrBlank() || engine == null || conversation == null) {
            throw IllegalStateException("Gemma LiteRT model is not initialized.")
        }

        val imageBytes = encodeBitmap(bitmap)
        val prompt = (
            "You are a child-safety classifier. Analyze the screenshot and return ONLY JSON with keys " +
                "sexual_content, violence, predatory_text, overall_risk. " +
                "All values must be floats from 0.0 to 1.0."
            )

        val response = conversation!!.sendMessage(
            Contents.of(
                Content.ImageBytes(imageBytes),
                Content.Text(prompt),
            )
        )
        val parsed = parseRiskJson(response.toString())

        return RiskSnapshot(
            timestampMs = System.currentTimeMillis(),
            sexual = parsed.first,
            violence = parsed.second,
            predatoryText = parsed.third,
            overall = parsed.fourth,
        )
    }

    private fun encodeBitmap(bitmap: Bitmap): ByteArray {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
        return stream.toByteArray()
    }

    private fun parseRiskJson(content: String): Quadruple {
        if (content.isBlank()) {
            throw IllegalStateException("Model response content is empty")
        }

        val normalized = content
            .removePrefix("```")
            .removePrefix("json")
            .removeSuffix("```")
            .trim()

        val root = JSONObject(normalized)
        return Quadruple(
            first = clamp(root.optDouble("sexual_content", 0.0)),
            second = clamp(root.optDouble("violence", 0.0)),
            third = clamp(root.optDouble("predatory_text", 0.0)),
            fourth = clamp(root.optDouble("overall_risk", 0.0)),
        )
    }

    private fun clamp(value: Double): Double = max(0.0, min(1.0, value))

    private data class Quadruple(
        val first: Double,
        val second: Double,
        val third: Double,
        val fourth: Double,
    )

    @Synchronized
    private fun closeResources() {
        try {
            conversation?.close()
        } catch (_: Exception) {
        }

        try {
            engine?.close()
        } catch (_: Exception) {
        }

        conversation = null
        engine = null
        modelPath = null
    }
}
