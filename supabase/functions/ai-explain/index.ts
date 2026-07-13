// Re-explains a question a different way.
//
// SECURITY: the OpenAI key lives HERE, as a server-side secret. It is never sent
// to the Flutter app — a key shipped in an APK or in web JS can be extracted by
// anyone who downloads it.
//
// ADR-008: the AI is NOT in the correctness path. We already know the answer (it
// was computed and verified offline). This endpoint only rephrases the teaching.
// It never scores, never grades, and never invents a new answer.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SYSTEM = `You are a patient maths tutor for a Grade 8 student in India (NCERT
"Ganita Prakash", chapters "A Square and A Cube" and "Power Play").

You will be given a question AND its correct answer. The answer is already known to be
correct — do not re-derive it, do not contradict it, and never claim it is wrong.

Your job is to explain the METHOD a different way from the textbook, so it clicks.

Rules:
- Only use methods taught in that book: prime factorisation (splitting factors into two
  identical groups for squares, three for cubes), repeated subtraction of odd numbers,
  estimation by trapping between known squares/cubes and using the last digit, and the
  laws of exponents. Do NOT use the long-division method for square roots — it is not in
  this book.
- Be concrete. Use a small real-world example a 13-year-old would recognise.
- Keep it under 120 words. Use simple language, short sentences.
- Write maths inside $...$ using LaTeX, e.g. $\\sqrt{144} = 12$, $2^{-3} = \\frac{1}{8}$.`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...CORS, "Content-Type": "application/json" },
    });

  if (!OPENAI_KEY) {
    return json({ error: "OPENAI_API_KEY is not set on the server" }, 500);
  }

  // Only signed-in users may spend our tokens.
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "not authenticated" }, 401);

  try {
    const { question, answer, ask } = await req.json();
    if (!question || !answer) {
      return json({ error: "question and answer are required" }, 400);
    }

    const user = [
      `Question: ${question}`,
      `Known correct answer: ${answer}`,
      ask ? `The student asks: ${ask}` : `The student did not understand. Explain the method another way.`,
    ].join("\n\n");

    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.4,
        max_tokens: 320,
        messages: [
          { role: "system", content: SYSTEM },
          { role: "user", content: user },
        ],
      }),
    });

    if (!res.ok) {
      const detail = await res.text();
      return json({ error: `OpenAI ${res.status}: ${detail.slice(0, 200)}` }, 502);
    }

    const data = await res.json();
    const explanation = data.choices?.[0]?.message?.content?.trim();
    if (!explanation) return json({ error: "empty response from OpenAI" }, 502);

    return json({ explanation });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
