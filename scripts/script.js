// Minor update for commit
console.log("🚀 script.js loaded");

// Import ethers.js (works in Hardhat or Remix's "Deploy & Run Scripts")
const { ethers } = require("ethers");

// Replace with your deployed contract address after deploying LifeStreamOracle
const CONTRACT_ADDRESS = "0xYourDeployedContractAddressHere";

// ABI (Application Binary Interface) - copy it from Remix compilation or artifacts
const CONTRACT_ABI = [
  "function createGoal(string _description, string _category, uint256 _deadline, uint256 _difficulty) external payable",
  "function completeGoal(uint256 _goalId, string _evidenceURI) external",
  "function verifyAndMintAchievement(uint256 _goalId) external",
  "function getGoalDetails(uint256 _goalId) external view returns (address,string,string,uint256,uint256,bool,bool,uint256,string,uint256)",
  "function getUserGoals(address _user) external view returns (uint256[])",
  "function getUserAchievementCount(address _user) external view returns (uint256)",
  "function getContractBalance() external view returns (uint256)"
];

async function main() {
  // ✅ 1. Setup provider & signer (Metamask / Hardhat / Ganache)
  const provider = new ethers.providers.Web3Provider(window.ethereum); 
  await provider.send("eth_requestAccounts", []); // request wallet connect
  const signer = provider.getSigner();

  // ✅ 2. Load contract instance
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

  // Example: Create a goal
  console.log("Creating a goal...");
  const tx = await contract.createGoal(
    "Finish Solidity Project",   // description
    "education",                 // category
    Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60, // deadline (7 days from now)
    3,                           // difficulty (1-5)
    { value: ethers.utils.parseEther("0.05") } // stake amount
  );
  await tx.wait();
  console.log("✅ Goal created!");

  // Example: Fetch goal details
  const goals = await contract.getUserGoals(await signer.getAddress());
  const latestGoalId = goals[goals.length - 1].toString();

  const goalDetails = await contract.getGoalDetails(latestGoalId);
  console.log("📌 Goal Details:", goalDetails);

  // Example: Complete the goal
  /*
  const tx2 = await contract.completeGoal(latestGoalId, "ipfs://your-proof-link");
  await tx2.wait();
  console.log("✅ Goal completed with evidence!");
  */
}

main().catch((err) => {
  console.error("❌ Error:", err);
});
