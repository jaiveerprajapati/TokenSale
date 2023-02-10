//SPDX-License-Identifier:Unlicensed

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
contract Crowdsale is Pausable, Ownable {
    using SafeERC20 for IERC20;

    uint256 private constant ICO_SUPPLY_PER_PHASE = 40000000 ether;
    uint256 private constant PHASES = 5;
    uint256 private constant PHASE_DURATION = 48 hours;
    uint256 private constant SOFT_CAP = 96500 ether;

    struct PhaseDetails {
        uint256 busdReceived;
        uint256 tokensSold;
        uint256 startTimestamp;
    }

    mapping(uint256 => PhaseDetails) public phases;
    mapping(uint256 => uint256) public tokenPrices;

    error InvalidPhase();
    error MinCap();
    error NotActive();
    error RefundNotActive();
    error NoRefundAvailable();
    error ExceedICOSupply();

    // Token contract
    IERC20 public swft;
    IERC20 public busd;
    // treasury that will receive the BUSD
    address public treasury;
    uint256 public currentPhase;

    uint256 public totalBUSDRaised;
    uint256 public totalTokensSold;
    uint256 public startTimestamp;

    mapping(address => uint256) public tokensBought;
    mapping(address => uint256) public busdSpent;

    modifier isRefundActive() {
        if (currentPhase != 5) revert RefundNotActive();

        PhaseDetails memory phase = phases[currentPhase];
        if (
            totalBUSDRaised > SOFT_CAP &&
            block.timestamp - (phase.startTimestamp) < PHASE_DURATION
        ) revert RefundNotActive();
        _;
    }

    // Events
    event Purchase(
        address indexed investor,
        uint256 tokenAmount,
        uint256 busdSpent
    );
    event Refund(
        address indexed investor,
        uint256 tokenAmount,
        uint256 busdSpent
    );

    constructor(
        address _swft,
        address _busd,
        address _treasury,
        address _owner
    ) {
        swft = IERC20(_swft);
        busd = IERC20(_busd);

        treasury = _treasury;
        transferOwnership(_owner);

        tokenPrices[1] = 1300000 gwei; // 0.0013 BUSD
        tokenPrices[2] = 2600000 gwei; // 0.0026 BUSD
        tokenPrices[3] = 3900000 gwei; // 0.0039 BUSD
        tokenPrices[4] = 5200000 gwei; // 0.0052 BUSD
        tokenPrices[5] = 6500000 gwei; // 0.0065 BUSD
    }

    function startCrowdsale() external onlyOwner {
        startTimestamp = block.timestamp;
        _updatePhase(1, startTimestamp);
    }

    function getPhaseDetails(uint256 _phase)
        external
        view
        returns (
            uint256 busdReceived,
            uint256 tokensSold,
            uint256 tokenPrice,
            uint256 totalBUSDRaisedTillNow
        )
    {
        PhaseDetails memory phase = phases[_phase];

        busdReceived = phase.busdReceived;
        tokensSold = phase.tokensSold;
        tokenPrice = tokenPrices[_phase];
        totalBUSDRaisedTillNow = totalBUSDRaised;
    }

    function getCurrentTokenPrice() public view returns (uint256) {
        return tokenPrices[currentPhase];
    }

    function getCurrentPhase() external view returns (uint256 _phase) {
        if (startTimestamp == 0) return 0;
        PhaseDetails memory phase = phases[currentPhase];

        _phase = currentPhase;
        if (block.timestamp - (phase.startTimestamp) > PHASE_DURATION) {
            uint256 incrementBy = (block.timestamp - phase.startTimestamp) /
                (PHASE_DURATION);
            incrementBy = incrementBy > 5 ? 5 : incrementBy;
            _phase = currentPhase + incrementBy;
        }

        _phase = _phase > 5 ? 5 : _phase;
    }

    function _beforePurchase() internal {
        PhaseDetails memory phase = phases[currentPhase];

        // solhint-disable
        if (block.timestamp - (phase.startTimestamp) > PHASE_DURATION) {
            uint256 incrementBy = (block.timestamp - phase.startTimestamp) /
                (PHASE_DURATION);

            _updatePhase(
                currentPhase + incrementBy,
                startTimestamp + (PHASE_DURATION * incrementBy)
            );
            return;
        }
    }

    // @notice this function updates the phase and start timestamp
    function _updatePhase(uint256 _to, uint256 _startTimestamp) internal {
        if (_to <= currentPhase) return;
        if (_to < 1 || _to > PHASES) revert InvalidPhase();

        currentPhase = currentPhase + 1;
        PhaseDetails storage phase = phases[currentPhase];
        phase.startTimestamp = _startTimestamp;
    }

    function _updatePurchaseDetails(
        uint256 _phase,
        uint256 _busd,
        uint256 _tokens
    ) internal {
        PhaseDetails storage phase = phases[_phase];

        phase.busdReceived = phase.busdReceived + _busd;
        phase.tokensSold = phase.tokensSold + _tokens;
    }

    function _executePurchase(uint256 _amount)
        internal
        returns (uint256 busdNeeded)
    {
        if (_amount > (ICO_SUPPLY_PER_PHASE * PHASES) - totalTokensSold)
            revert ExceedICOSupply();

        uint256 total = _amount;

        while (total > 0) {
            PhaseDetails memory phase = phases[currentPhase];
            uint256 tokenPrice = getCurrentTokenPrice();
            uint256 diff = ICO_SUPPLY_PER_PHASE - phase.tokensSold;

            uint256 multiplier;
            if (diff < total) {
                multiplier = diff;
            } else {
                multiplier = total;
            }
            uint256 phaseBUSD = (multiplier * tokenPrice) / 1 ether;
            _updatePurchaseDetails(currentPhase, phaseBUSD, multiplier);
            total -= multiplier;
            busdNeeded += phaseBUSD;

            if (total > 0) _updatePhase(currentPhase + 1, block.timestamp);
        }
    }

    function purchase(uint256 amount) external whenNotPaused {
        _beforePurchase();

        uint256 busdNeeded = _executePurchase(amount);
        if (busdNeeded < 50 ether) revert MinCap();

        tokensBought[msg.sender] = tokensBought[msg.sender] + amount;
        busdSpent[msg.sender] = busdSpent[msg.sender] + busdNeeded;

        totalBUSDRaised += busdNeeded;
        totalTokensSold += amount;

        IERC20(busd).safeTransferFrom(msg.sender, treasury, busdNeeded);
        IERC20(swft).safeTransferFrom(treasury, msg.sender, amount);

        emit Purchase(msg.sender, amount, busdNeeded);
    }

    // @notice treasury needs to approve busd tokens to the contract in case sale
    // does not reach hard cap.
    function refund() external isRefundActive {
        if (tokensBought[msg.sender] == 0 && totalBUSDRaised > 0)
            revert NoRefundAvailable();

        uint256 tokensToReturn = tokensBought[msg.sender];
        uint256 busdToReturn = busdSpent[msg.sender];

        tokensBought[msg.sender] = 0;
        busdSpent[msg.sender] = 0;

        totalBUSDRaised -= busdToReturn;

        IERC20(swft).safeTransferFrom(msg.sender, treasury, tokensToReturn);
        IERC20(busd).safeTransferFrom(treasury, msg.sender, busdToReturn);

        emit Refund(msg.sender, tokensToReturn, busdToReturn);
    }

    // @dev this function can be used to remove tokens and eth sent to the
    // contract by mistake.
    function inCaseTokensGetStuck(address token) external onlyOwner {
        if (token == address(0))
            return payable(owner()).transfer(address(this).balance);

        IERC20(token).safeTransfer(
            owner(),
            IERC20(token).balanceOf(address(this))
        );
    }
}
