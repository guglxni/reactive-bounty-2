import { ethers } from "ethers";
import config from "./config.js";

async function main() {
    const provider = new ethers.JsonRpcProvider(config.NETWORKS.sepolia.rpc);
    const manager = new ethers.Contract(config.CONTRACTS.manager, config.ABIS.manager, provider);
    const wallet = "0xDDe9D31a31d6763612C7f535f51E5dC9f830682e";
    
    const pos = await manager.getPosition(wallet);
    const state = Number(pos.state);
    const leverage = Number(pos.currentLeverage) / 1e18;
    const states = ["IDLE", "LOOPING", "UNWINDING"];
    
    console.log("Position State:", states[state] || state);
    console.log("Current Leverage:", leverage.toFixed(4) + "x");
    console.log("Has Debt:", leverage > 1);
}

main().catch(console.error);
