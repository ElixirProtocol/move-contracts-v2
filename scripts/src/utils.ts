import { StructType } from "./types";

export function normalizeAddress(address: string): string {
  const hex = address.startsWith("0x") ? address.slice(2) : address;
  return "0x" + hex.padStart(64, "0").toLowerCase();
}

export function trim0xPrefix(address: string): string {
  return address.startsWith("0x") ? address.slice(2) : address;
}

// Expected format: "0x123::module::Name"
export function parseStructType(type: string): StructType {
  const parts = type.split("::");
  if (parts.length !== 3) {
    throw new Error(
      `Invalid struct type format: ${type}. Expected format: "0x123::module::Name"`
    );
  }

  return {
    address: parts[0],
    module: parts[1],
    name: parts[2],
  };
}

// Helper to get struct tag string (like type_name::get<T>())
export function getStructTypeString(structType: StructType): string {
  return `${trim0xPrefix(normalizeAddress(structType.address))}::${
    structType.module
  }::${structType.name}`;
}
