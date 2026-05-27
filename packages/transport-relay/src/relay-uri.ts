export interface RelayAssociationUri {
  version: "2";
  transport: "relay";
  relay: string;
  room: string;
  secret: string;
  origin: string;
  expiresAt: string;
}

export function createRelayAssociationUri(input: RelayAssociationUri): string {
  const url = new URL("wap://associate");
  url.searchParams.set("version", input.version);
  url.searchParams.set("transport", input.transport);
  url.searchParams.set("relay", input.relay);
  url.searchParams.set("room", input.room);
  url.searchParams.set("secret", input.secret);
  url.searchParams.set("origin", input.origin);
  url.searchParams.set("expiresAt", input.expiresAt);
  return url.toString();
}

export function parseRelayAssociationUri(uri: string): RelayAssociationUri {
  let url: URL;
  try {
    url = new URL(uri);
  } catch {
    throw new Error("Invalid WAP connection URI");
  }

  if (url.protocol !== "wap:" || url.hostname !== "associate") {
    throw new Error("Invalid WAP connection URI");
  }

  const version = requiredParam(url, "version");
  const transport = requiredParam(url, "transport");
  const relay = requiredParam(url, "relay");
  const room = requiredParam(url, "room");
  const secret = requiredParam(url, "secret");
  const origin = requiredParam(url, "origin");
  const expiresAt = requiredParam(url, "expiresAt");

  if (version !== "2")
    throw new Error("Unsupported WAP connection URI version");
  if (transport !== "relay")
    throw new Error("Unsupported WAP connection URI transport");
  if (Number.isNaN(Date.parse(expiresAt)))
    throw new Error("Invalid WAP connection URI expiry");

  return { version, transport, relay, room, secret, origin, expiresAt };
}

function requiredParam(url: URL, name: string): string {
  const value = url.searchParams.get(name);
  if (!value) {
    throw new Error(`Missing WAP connection URI parameter: ${name}`);
  }
  return value;
}
