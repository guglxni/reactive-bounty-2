import { ethers } from "ethers";
import config from "./config.js";

async function main() {
    // Use a public RPC that allows larger log queries
    const provider = new ethers.JsonRpcProvider("https://rpc.sepolia.org");
    const manager = new ethers.Contract(config.CONTRACTS.manager, config.ABIS.manager, provider);
    
    const currentBlock = await provider.getBlockNumber();
    console.log("Current block:", currentBlock);
    console.log("Checking last 1000 blocks for PositionUpdated events...\n");
    
    const filter = manager.filters.PositionUpdated();
    const events = await manager.queryFilter(filter, currentBlock - 1000, currentBlock);
    
    events.forEach(e => {
        console.log("=== Event at block", e.blockNumber, "===");
        console.log("User:", e.args[0]);
        console.log("State:", ["IDLE", "LOOPING", "UNWINDING", "EMERGENCY"][Number(e.args[4])] || e.args[4]);
        console.log("Leverage:", (Number(e.args[3]) / 1e18).toFixed(4) + "x");
        console.log("TX:", e.transactionHash);
        console.log("");
    });
    
    if (events.length === 0) {
        console.log("No PositionUpdated events found in last 200 blocks");
    }
}
main().catch(console.error);
