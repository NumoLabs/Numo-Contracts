import { CallData, cairo } from 'starknet';
import fs from 'fs';

// Contract parameters
// Name and Symbol as hex values (ByteArray serialized)
const nameHex = "0x4e756d6f205661756c742077425443"; // "Numo Vault wBTC"
const symbolHex = "0x4e5677425443"; // "NVwBTC"
const asset = "0x03Fe2b97C1Fd336E750087D68B9b867997Fd64a2661fF3ca5A7C771641e8e7AC";
const access_control = "0x038d9c69eed034ba4765920f7b3c9d57acf8ef447230c4529ddea660d42a6487";

// PoolProps (1 pool) - pool_id is now the pool address (ContractAddress), not a felt252 ID
const pool_id = "0x451fe483d5921a2919ddd81d0de6696669bccdacd859f72a4fba7656b97c3b5"; // Pool address (ContractAddress)
const max_weight = 10000; // 100% in bps
const v_token = "0x4ecb0667140b9f45b067d026953ed79f22723f1cfac05a7b26c3ac06c88f56c"; // wBTC vToken (correct)

// Settings
const default_pool_index = 0;
const fee_bps = 100;
const fee_receiver = "0x0466617918874f335728dbe0903376d1d9756137dd70e927164af4855e1ddae1";

// In V2, constructor only needs oracle (not vesuStruct)
// Only oracle is used for harvest operations
const oracle = "0xfe4bfb1b353ba51eb34dff963017f94af5a5cf8bdf3dfc191c504657f3c05"; // Oracle address for harvest

// Function to serialize ByteArray following starknet.js v6 structure
function serializeByteArray(str) {
  const bytes = Buffer.from(str, 'utf8');
  const data = [];
  
  // Convert bytes to 31-byte chunks (Cairo bytes31)
  for (let i = 0; i < bytes.length; i += 31) {
    const chunk = bytes.slice(i, i + 31);
    const padded = Buffer.alloc(31);
    chunk.copy(padded);
    data.push('0x' + padded.toString('hex'));
  }
  
  // Calculate pending word and length
  const pendingWordLen = bytes.length % 31;
  let pendingWord = '0x00';
  if (pendingWordLen > 0) {
    const lastChunk = bytes.slice(bytes.length - pendingWordLen);
    const padded = Buffer.alloc(31);
    lastChunk.copy(padded);
    pendingWord = '0x' + padded.toString('hex');
  }
  
  return {
    data_len: data.length,
    data: data,
    pending_word: pendingWord,
    pending_word_len: pendingWordLen
  };
}

try {
  // Name and Symbol as ByteArray
  // Name: "Numo Vault wBTC" = 16 bytes (< 31 bytes, so goes only in pending_word)
  // Symbol: "NVwBTC" = 6 bytes (< 31 bytes, so goes only in pending_word)
  // ByteArray format: data_len, data[], pending_word, pending_word_len
  // For strings < 31 bytes: data_len = 0, data is empty, pending_word contains the string
  
  // Name ByteArray (16 bytes - fits in pending_word only)
  // "Numo Vault wBTC" = 16 bytes = 32 hex chars (without 0x)
  // Need to pad to 31 bytes = 62 hex chars (without 0x)
  const nameDataLen = 0; // No data array needed
  const nameHexWithoutPrefix = "4e756d6f205661756c742077425443"; // 32 hex chars = 16 bytes
  const namePendingWord = "0x" + nameHexWithoutPrefix + "0".repeat(62 - nameHexWithoutPrefix.length); // Pad to 62 hex chars = 31 bytes
  const namePendingWordLen = 16;
  
  // Symbol ByteArray (6 bytes - fits in pending_word only)
  // "NVwBTC" = 6 bytes = 12 hex chars (without 0x)
  // N=4e, V=56, w=77, B=42, T=54, C=43
  // Need to pad to 31 bytes = 62 hex chars (without 0x)
  const symbolDataLen = 0; // No data array needed
  const symbolHexWithoutPrefix = "4e5677425443"; // "NVwBTC" = 12 hex chars = 6 bytes
  const symbolPendingWord = "0x" + symbolHexWithoutPrefix + "0".repeat(62 - symbolHexWithoutPrefix.length); // Pad to 62 hex chars = 31 bytes
  const symbolPendingWordLen = 6;
  
  // Create the constructor calldata manually
  const calldata = [
    // name: ByteArray
    nameDataLen, // 0 - no data array
    namePendingWord, // String padded to 31 bytes
    namePendingWordLen, // Actual length: 20
    
    // symbol: ByteArray
    symbolDataLen, // 0 - no data array
    symbolPendingWord, // String padded to 31 bytes
    symbolPendingWordLen, // Actual length: 6
    
    // asset: ContractAddress
    asset,
    
    // access_control: ContractAddress
    access_control,
    
    // allowed_pools: Array<PoolProps>
    1, // array length
    pool_id,
    max_weight,
    v_token,
    
    // settings: Settings
    default_pool_index,
    fee_bps,
    fee_receiver,
    
    // oracle: ContractAddress (V2 only needs oracle, not vesuStruct)
    oracle
  ];
  
  console.log("\nSerialized calldata:");
  calldata.forEach((param, index) => {
    console.log(`${index}: ${param}`);
  });
  
  // Write to file
  fs.writeFileSync('calldata_starknetjs.txt', calldata.join('\n'));
  console.log("\nCalldata written to calldata_starknetjs.txt");
  
  // Generate sncast command
  const sncastCmd = [
    "sncast", "--account", "aguilar1x", "deploy",
    "--url", "https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_9/c0P2DVGVr0OOBtgc3tSqm",
    "--class-hash", "0x07b23ad6a013abcf5858942b457fc51f99c15c14e6dd88fa86d8a3c9da45aedf",
    "--constructor-calldata"
  ].concat(calldata);
  
  console.log("\nSncast command:");
  console.log(sncastCmd.join(' '));
  
} catch (error) {
  console.error("Error:", error.message);
  process.exit(1);
}
