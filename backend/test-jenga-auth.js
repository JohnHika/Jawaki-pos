const fs = require("fs");

const env = {};

for (const line of fs.readFileSync(".env", "utf8").split(/\r?\n/)) {
  const cleaned = line.trim();

  if (!cleaned || cleaned.startsWith("#") || !cleaned.includes("=")) {
    continue;
  }

  const equalsPosition = cleaned.indexOf("=");
  const name = cleaned.slice(0, equalsPosition).trim();
  let value = cleaned.slice(equalsPosition + 1).trim();

  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    value = value.slice(1, -1);
  }

  env[name] = value;
}

async function testConnection() {
  try {
    const response = await fetch(
      "https://uat.finserve.africa/authentication/api/v3/authenticate/merchant",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Api-Key": env.JENGA_API_KEY,
        },
        body: JSON.stringify({
          merchantCode: env.JENGA_MERCHANT_CODE,
          consumerSecret: env.JENGA_CONSUMER_SECRET,
        }),
      }
    );

    const text = await response.text();
    let data = {};

    try {
      data = JSON.parse(text);
    } catch {}

    if (response.ok && data.accessToken) {
      console.log("SUCCESS: Jenga connection works");
    } else {
      console.log(
        "FAILED:",
        response.status,
        data.message || data.error || "Jenga rejected the request"
      );
    }
  } catch (error) {
    console.log("FAILED:", error.message);
  }
}

testConnection();