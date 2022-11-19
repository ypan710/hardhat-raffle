const {messagePrefix} = require("@ethersproject/hash")
const {assert, expect} = require("chai")
const {network, getNamedAccounts, deployments, ethers} = require("hardhat")
const {developmentChains, networkConfig} = require("../../helper-hardhat-config")

!developmentChains.includes(network.name) ? describe.skip : describe("Raffle Unit Tests", async function () {
    let raffle,
        vrfCoordinatorV2Mock,
        raffleEntranceFee,
        interval
    const chainId = network.config.chainId;
beforeEach(async function () {
    const {deployer} = await getNamedAccounts()
    await deployments.fixture(["all"])
    raffle = await ethers.getContract("Raffle", deployer)
    vrfCoordinatorV2Mock = await ethers.getContract("VRFCoordinatorV2Mock", deployer)
    raffleEntranceFee = await raffle.getEntranceFee()
    interval = await raffle.getInterval()
})

describe("constructor", function () {
    it("initializes the raffle correctly", async function () {
        const raffleState = await raffle.getRaffleState()
        assert.equal(raffleState.toString(), "0")
        assert.equal(interval.toString(), networkConfig[chainId]["interval"])
    })
})

describe("enterRaffle", function () {
    it("reverts when you don't pay enough", async function () {
        await expect(raffle.enterRaffle()).to.be.revertedWith("Raffle__NotEnoughETHEntered")
    })
    it("records players when they enter", async function () {
        const {deployer} = await getNamedAccounts()
        await raffle.enterRaffle({value: raffleEntranceFee})
        const playerFromContract = await raffle.getPlayer(0)
        assert.equal(playerFromContract, deployer)
    })
    it("emits event on enter", async function () {
        await expect(raffle.enterRaffle({value: raffleEntranceFee})).to.emit(raffle, "RaffleEnter")
    })
    it("doesn't allow entrance when raffle is calculating", async function () {
        await raffle.enterRaffle({value: raffleEntranceFee})
        await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
        await network.provider.send("evm_mine", [])
        // pretend to be a chainlink keeper
        await raffle.performUpkeep([])
        await expect(raffle.enterRaffle({value: raffleEntranceFee})).to.be.revertedWith("Raffle__NotOpen")
    })
    describe("checkUpkeep", function () {
        it("returns false if people haven't sent any ETH", async function () {
            await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
            await network.provider.send("evm_mine", [])
            // pretend to be a chainlink keeper
            const {upkeepNeeded} = await raffle.callStatic.checkUpkeep([]) // return upkeepneeded
            assert(!upkeepNeeded)
        })
        it("returns false if raffle isn't open", async function () {
            await raffle.enterRaffle({value: raffleEntranceFee})
            await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
            await network.provider.send("evm_mine", [])
            // pretend to be a chainlink keeper
            await raffle.performUpkeep([])
            const raffleState = await raffle.getRaffleState()
            const {upkeepNeeded} = await raffle.callStatic.checkUpkeep([]) // return upkeepneeded
            assert.equal(raffleState.toString(), "1")
            assert.equal(upkeepNeeded, false)
        })
        it("returns false if enough time hasn't passed", async () => {
            await raffle.enterRaffle({value: raffleEntranceFee})
            await network.provider.send("evm_increaseTime", [interval.toNumber() - 5]) // use a higher number here if this test fails
            await network.provider.request({method: "evm_mine", params: []})
            const {upkeepNeeded} = await raffle.callStatic.checkUpkeep("0x") // upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers)
            assert(!upkeepNeeded)
        })
        it("returns true if enough time has passed, has players, eth, and is open", async () => {
            await raffle.enterRaffle({value: raffleEntranceFee})
            await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
            await network.provider.request({method: "evm_mine", params: []})
            const {upkeepNeeded} = await raffle.callStatic.checkUpkeep("0x") // upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers)
            assert(upkeepNeeded)
        })
    })
    describe("performUpkeep", function () {
        it("can only run if checkupkeep is true", async function () {
            await raffle.enterRaffle({value: raffleEntranceFee})
            await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
            await network.provider.request({method: "evm_mine", params: []})
            const tx = await raffle.performUpkeep([])
            assert(tx)
        })
        it("reverts when checkupkeep is false", async function () {
            await expect(raffle.performUpkeep([])).to.be.revertedWith("Raffle__UpkeepNotNeeded")
        })
        it("updates the raffle state, emits an event, calls the vrfcoordinato", async function () {
            await raffle.enterRaffle({value: raffleEntranceFee})
            await network.provider.send("evm_increaseTime", [interval.toNumber() + 1])
            await network.provider.request({method: "evm_mine", params: []})
            const txResponse = await raffle.performUpkeep([])
            const txReceipt = await txResponse.wait(1)
            const requestId = txReceipt.events[1].args.requestId
            assert(requestId.toNumber())
        })
    })

})})
