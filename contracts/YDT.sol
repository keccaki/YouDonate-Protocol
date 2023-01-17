// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IYDTSwapLottery.sol";
import "./interfaces/ISimiDAO.sol";
import "./interfaces/IYDTData.sol";
import "./interfaces/IYDTSwapLottery.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./utils/ERC2771Context.sol";

// Import this file to use console.log
import "hardhat/console.sol";

contract YDT is ERC2771Context, AccessControl, ERC20, ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    bool public isDaoSet;
    bool public isRydtSet;
    bool public isLotterySet;
    address teamAddress;
    mapping(address => uint256) public totalDeposit;
    uint256 YDTpoolValue;

    ISimiDAO public simiDAO;

    IYDTSwapLottery public ydtLottery;

    IYDTData public ydtInterface;

    event DonationMade(
        address indexed donor,
        uint indexed donationId,
        uint256 amount
    );

    event InjectedFunds(
        uint256 indexed _lotteryId,
        uint256 _amount
    );

    event SimiDAOUpdated(address indexed _simiDAO);

    event LotteryUpdated(address indexed _lottery);

    event ClaimedPrize(
        address indexed _user,
        address indexed _token,
        uint256 _amount
    );

    event SetTeamAddress(
        address indexed _team
    );
    
    constructor (string memory _name, string memory _symbol, address _iydt, address _trustedForwarder) ERC20(_name, _symbol) ERC2771Context(_trustedForwarder, _iydt) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _mint(msg.sender, 50000000 * 10**uint(decimals()));
        _mint(address(this), 50000000 * 10**uint(decimals()));
        ydtInterface = IYDTData(_iydt);
    }

    /**
     * @notice set address of the team funding
     * @param _team company address
     */
    function setTeamAddress(address _team) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Access Restricted");
        require(
            _team != address(0),
            "YDT: Invalid address for team"
        );
        teamAddress = _team;
        emit SetTeamAddress(_team);
    }
    

    function getPriceData(address _token, uint256 _amount) public view returns (uint256) {
        (,
        uint128 decimals,
        ,
        bool accepted,
        bool isChainLinkFeed,
        address priceFeedAddress,
        ) = ydtInterface.acceptedTokens(_token);
        require(accepted, "Token not accepted");
        uint256 _price;
        if (isChainLinkFeed) {
            AggregatorV3Interface chainlinkFeed = AggregatorV3Interface(
                priceFeedAddress
            );
            (
                ,int256 price,,,
            ) = chainlinkFeed.latestRoundData();
            _price = uint256(price);
        } 
        uint256 price = _toPrecision(
            _amount,
            uint256(_price),
            decimals
        );
        return price;
    }
    /**
     * @notice trim or add number for certain precision as required
     * @param _amount amount/number that needs to be modded
     * @param n new desired precision
     * @return price of underlying token in usd
     */
    function _toPrecision(
        uint256 _amount,
        uint256 _usd,
        uint128 n
    ) internal pure returns (uint256) {
        uint256 tokenUnit = _amount / (10**uint128(n-3));
        uint256 total = tokenUnit * _usd;
        total = total / (10**uint128(3));
        return total;
    }


    function donateToProject(uint _proposalId, uint256 _amount, address _token) public nonReentrant {
        require(ydtInterface.isAcceptedToken(_token), "Token not accepted");
        require(isDaoSet, "DAO has not been set");
        require(simiDAO.isValidForDonation(_proposalId), "Invalid Project");
        IERC20 erc20 = IERC20(_token);
        require(
            erc20.allowance(msg.sender, address(this)) >= _amount,
            "Insufficient allowance"
        );
        address proposer = simiDAO.getApprovedDonation(_proposalId).proposer;
        uint256 projectShare = (_amount * 95) / 100;
        uint256 teamShare = (_amount * 5) / 100;
        erc20.safeTransferFrom(msg.sender, proposer, projectShare);
        erc20.safeTransferFrom(msg.sender, teamAddress, teamShare);
        uint256 fund = getPriceData(_token, _amount);
        uint256 donationValue = fund * 95 / 100;
        YDTpoolValue += fund * 5 / 100;
        simiDAO.receivedDonation(_proposalId, donationValue);
        uint256 ydtFund = fund * (10**uint128(10));
        _transfer(address(this),msg.sender, ydtFund);
        totalDeposit[_token] += _amount;
        emit DonationMade(msg.sender, _proposalId, projectShare);
    }

    function injectFundToPool(uint256 _amount, uint256 _lotteryId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isLotterySet, "Lottery has not been set");
        require(_amount <= YDTpoolValue, "Insufficient Amount");
        ydtLottery.injectFunds(_lotteryId, _amount);
        YDTpoolValue -= _amount;
        emit InjectedFunds(_lotteryId, _amount);
    }

    // function claimLotteryPrize(uint256 _amount, address _token) public {
    //     (string memory symbol,
    //     uint128 decimals,
    //     ,
    //     bool accepted,
    //     bool isChainLinkFeed,
    //     address priceFeedAddress,
    //     uint128 priceFeedPrecision) = ydtInterface.acceptedTokens(_token);
    //     require(accepted, "Token not accepted");
    //     require(RYDTtoken.balanceOf(msg.sender) >= _amount, "Insufficient balance");
    //     require(RYDTtoken.allowance(msg.sender, address(this)) >= _amount, "Insufficient allowance");
    //     RYDTtoken.safeTransferFrom(msg.sender, address(this), _amount);
    //     IERC20 erc20 = IERC20(_token);
    //     uint256 _price;
    //     if (isChainLinkFeed) {
    //         AggregatorV3Interface chainlinkFeed = AggregatorV3Interface(
    //             priceFeedAddress
    //         );
    //         (
    //             ,int256 price,,,
    //         ) = chainlinkFeed.latestRoundData();
    //         _price = uint256(price);
    //     }
    //     int128 decimalFactor = int128(priceFeedPrecision) - int128(decimals);
    //     uint256 tokenUnit = _amount / (10**uint128(10));
    //     uint256 total = tokenUnit / _price;
    //     total = total * (10**uint128(priceFeedPrecision));
    //     if (decimalFactor > 0) {
    //         total = total / (10**uint128(decimalFactor));
    //     } else if (decimalFactor < 0) {
    //         total = total * (10**uint128(-1 * decimalFactor));
    //     }
    //     erc20.safeTransfer(msg.sender, total);
    //     YDTpoolValue -= _amount;
    //     YDTpoolFund[_token] -= total;
    //     emit ClaimedPrize(msg.sender, _token, _amount);
    // }
    /**
     * @notice update simiDAO address
     * @param _simiDAO new simiDAO address
     */
    function updateSimiDAO(address _simiDAO) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _simiDAO != address(0),
            "Invalid simiDAO address"
        );
        simiDAO = ISimiDAO(_simiDAO);
        isDaoSet = true;
        emit SimiDAOUpdated(_simiDAO);
    }
    /**
     * @notice update lottert contract address
     * @param _lottery new simiDAO token address
     */
    function updateLotteryAddress(address _lottery) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _lottery != address(0),
            "invalid lottery address"
        );
        ydtLottery = IYDTSwapLottery(_lottery);
        isLotterySet = true;
        emit LotteryUpdated(_lottery);

    }
    // unchecked iterator increment for gas optimization
    function unsafeInc(uint x) private pure returns (uint) {
        unchecked { return x + 1;}
    }


    function _msgSender() internal view override(ERC2771Context, Context)
      returns (address sender) {
      sender = ERC2771Context._msgSender();
    }
    function _msgData() internal view override(ERC2771Context, Context)
      returns (bytes calldata) {
      return ERC2771Context._msgData();
    }
}
