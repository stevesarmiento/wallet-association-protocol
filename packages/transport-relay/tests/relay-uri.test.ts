import { describe, expect, it } from "vitest";
import { createRelayAssociationUri, parseRelayAssociationUri } from "../src";

describe("relay association URI", () => {
  it("round trips relay URI fields", () => {
    const uri = createRelayAssociationUri({
      version: "2",
      transport: "relay",
      relay: "ws://127.0.0.1:9000/v2/relay",
      room: "room",
      secret: "secret",
      origin: "https://app.example",
      expiresAt: "2026-06-01T00:00:00.000Z",
    });

    expect(parseRelayAssociationUri(uri)).toEqual({
      version: "2",
      transport: "relay",
      relay: "ws://127.0.0.1:9000/v2/relay",
      room: "room",
      secret: "secret",
      origin: "https://app.example",
      expiresAt: "2026-06-01T00:00:00.000Z",
    });
  });

  it("rejects non-WAP URIs", () => {
    expect(() => parseRelayAssociationUri("https://app.example")).toThrow();
  });
});
