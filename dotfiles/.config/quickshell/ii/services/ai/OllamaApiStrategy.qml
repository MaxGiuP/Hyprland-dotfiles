import QtQuick
import qs.services.ai

ApiStrategy {
    id: strat
    property bool isReasoning: false

    function reset() {
        isReasoning = false;
    }

    function buildEndpoint(model) {
        // es.: http://localhost:11434/v1/chat/completions
        return model.endpoint;
    }

    // /v1/chat/completions stile OpenAI compatibile con Ollama
    function buildRequestData(model, messages, systemPrompt, temperature, tools) {
        const chatMessages = [];
        if (systemPrompt && systemPrompt.length > 0) {
            chatMessages.push({ role: "system", content: systemPrompt });
        }
        for (let i = 0; i < messages.length; i++) {
            const m = messages[i];
            chatMessages.push({
                role: m.role, // "user" | "assistant"
                content: m.rawContent || m.content || ""
            });
        }

        let base = {
            model: model.model,
            messages: chatMessages,
            stream: true,
            temperature: temperature
        };

        if (model.extraParams) {
            base = Object.assign({}, base, model.extraParams);
        }
        return base;
    }

    // Nessuna auth per Ollama locale
    function buildAuthorizationHeader(apiKeyEnvVarName) {
        return "";
    }

    // Parser streaming SSE. Rimuove "data:", gestisce reasoning e chiusura <think>.
    function parseResponseLine(line, message) {
        let s = line.trim();
        if (s.length === 0) return {};
        if (s.startsWith(":")) return {}; // commento SSE

        // Rimuovi "data:" PRIMA di controllare [DONE]
        if (s.startsWith("data:")) {
            s = s.slice(5).trim();
            if (s.length === 0) return {};
        }

        // Gestisci [DONE] dopo aver tolto "data:"
        if (s === "[DONE]") {
            if (isReasoning) {
                const endBlock = "\n\n</think>\n\n";
                message.content += endBlock;
                message.rawContent += endBlock;
                isReasoning = false;
            }
            return { finished: true };
        }

        try {
            const j = JSON.parse(s);

            if (j.done === true) {
                if (isReasoning) {
                    const endBlock2 = "\n\n</think>\n\n";
                    message.content += endBlock2;
                    message.rawContent += endBlock2;
                    isReasoning = false;
                }
                return { finished: true };
            }

            const delta = j?.choices?.[0]?.delta || {};
            const content = delta.content || "";
            const reasoning = delta.reasoning || delta.reasoning_content || "";

            let chunk = "";

            if (reasoning && reasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const start = "\n\n<think>\n\n";
                    message.content += start;
                    message.rawContent += start;
                }
                chunk = reasoning;
            } else if (content && content.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const end = "\n\n</think>\n\n";
                    message.content += end;
                    message.rawContent += end;
                }
                chunk = content;
            } else {
                return {};
            }

            message.content += chunk;
            message.rawContent += chunk;

            return {};
        } catch (e) {
            console.log("[Ollama] parseResponseLine error:", e);

            // Se per qualche motivo ci ritroviamo ancora [DONE] qui, ignoralo
            if (s === "[DONE]") {
                return { finished: true };
            }

            // fallback grezzo: append solo se non è un token di controllo
            message.content += s;
            message.rawContent += s;
            return {};
        }
    }

    function onRequestFinished(message) {
        if (isReasoning) {
            const endBlock = "\n\n</think>\n\n";
            message.content += endBlock;
            message.rawContent += endBlock;
            isReasoning = false;
        }
        return { finished: true };
    }
}
