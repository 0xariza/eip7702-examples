// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SmartAccount} from "src/smartAccount/SmartAccount.sol";
import {FeeManager} from "src/feeManager/FeeManager.sol";
import {IFeeManager} from "src/feeManager/IFeeManager.sol";

interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

contract MockERC20 {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}

contract SmartAccountFeeTest is Test {
    address internal constant ENTRYPOINT = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    FeeManager feeManager;
    SmartAccount account;
    address treasury;
    address feeSigner;
    uint256 constant FEE_SIGNER_PK = 0xFEE;

    address recipient = address(0xBEEF);
    MockERC20 token;

    function setUp() public {
        treasury = address(0xA11CE);
        feeSigner = vm.addr(FEE_SIGNER_PK);

        // Deploy FeeManager
        feeManager = new FeeManager(
            treasury,
            50,             // systemFeePercentage = 0.5%
            1000,           // maximumFeePercentage = 10%
            feeSigner,      // fee signer
            address(this)   // initial owner
        );

        // Deploy account pointing to feeManager and entrypoint
        account = new SmartAccount(address(feeManager), ENTRYPOINT);

        // Fund account with ETH
        vm.deal(address(account), 100 ether);

        // Deploy and fund token to account
        token = new MockERC20();
        token.mint(address(account), 1_000_000 ether);
    }

    function _entryPointPrank() internal {
        vm.startPrank(ENTRYPOINT);
    }

    function _stopPrank() internal {
        vm.stopPrank();
    }

    function test_ETH_transfer_default_fee() public {
        uint256 amount = 1 ether;
        uint256 systemBps = feeManager.systemFeePercentage();
        uint256 feeAmount = (amount * systemBps) / 10000;
        uint256 totalRequired = amount + feeAmount;

        // Build permit with system fee bps
        IFeeManager.FeePermit memory p = IFeeManager.FeePermit({
            account: address(account),
            to: recipient,
            amount: amount,
            feeBps: systemBps,
            nonce: 111,
            deadline: block.timestamp + 1 hours
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.FEE_PERMIT_TYPEHASH(),
            p.account,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        uint256 balBeforeAccount = address(account).balance;
        uint256 balBeforeTreasury = treasury.balance;
        uint256 balBeforeRecipient = recipient.balance;

        _entryPointPrank();
        account.transferETH(recipient, amount, systemBps, p.nonce, p.deadline, sig);
        _stopPrank();

        assertEq(address(treasury).balance, balBeforeTreasury + feeAmount, "treasury fee");
        assertEq(recipient.balance, balBeforeRecipient + amount, "recipient amount");
        assertEq(address(account).balance, balBeforeAccount - totalRequired, "account decreased by total");
    }

    function test_ETH_transfer_custom_fee_via_permit() public {
        uint256 amount = 2 ether;
        uint256 customBps = 100; // 1%

        // Build permit
        IFeeManager.FeePermit memory p = IFeeManager.FeePermit({
            account: address(account),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: 123,
            deadline: block.timestamp + 1 hours
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.FEE_PERMIT_TYPEHASH(),
            p.account,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        uint256 feeAmount = (amount * customBps) / 10000;
        uint256 totalRequired = amount + feeAmount;

        uint256 balBeforeAccount = address(account).balance;
        uint256 balBeforeTreasury = treasury.balance;
        uint256 balBeforeRecipient = recipient.balance;

        _entryPointPrank();
        account.transferETH(recipient, amount, customBps, p.nonce, p.deadline, sig);
        _stopPrank();

        assertEq(address(treasury).balance, balBeforeTreasury + feeAmount, "treasury fee");
        assertEq(recipient.balance, balBeforeRecipient + amount, "recipient amount");
        assertEq(address(account).balance, balBeforeAccount - totalRequired, "account decreased by total");

        // Reuse should fail (nonce used)
        _entryPointPrank();
        vm.expectRevert();
        account.transferETH(recipient, amount, customBps, p.nonce, p.deadline, sig);
        _stopPrank();
    }

    function test_ETH_permit_expired_reverts() public {
        uint256 amount = 1 ether;
        uint256 customBps = 100; // 1%

        IFeeManager.FeePermit memory p = IFeeManager.FeePermit({
            account: address(account),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: 1,
            deadline: block.timestamp - 1 // expired
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.FEE_PERMIT_TYPEHASH(),
            p.account,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        _entryPointPrank();
        vm.expectRevert();
        account.transferETH(recipient, amount, customBps, p.nonce, p.deadline, sig);
        _stopPrank();
    }

    function test_ERC20_transfer_with_default_fee() public {
        uint256 amount = 1000 ether;
        uint256 systemBps = feeManager.systemFeePercentage();
        uint256 feeAmount = (amount * systemBps) / 10000;
        uint256 totalRequired = amount + feeAmount;

        uint256 balBeforeAccount = token.balanceOf(address(account));
        uint256 balBeforeTreasury = token.balanceOf(treasury);
        uint256 balBeforeRecipient = token.balanceOf(recipient);

        // Approve FeeManager to pull tokens from account
        _entryPointPrank();
        // Use execute to call token.approve from the account
        bytes memory approveData = abi.encodeWithSelector(IERC20Minimal.approve.selector, address(feeManager), totalRequired);
        account.execute(address(token), 0, approveData);
        _stopPrank();

        _entryPointPrank();
        // Use permit path for tokens (in current architecture smart account delegates to feeManager internally)
        // Build token permit
        uint256 customBps = 0;
        uint256 nonce = 321;
        uint256 deadline = block.timestamp + 1 hours;

        IFeeManager.TokenFeePermit memory p = IFeeManager.TokenFeePermit({
            account: address(account),
            token: address(token),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.TOKEN_FEE_PERMIT_TYPEHASH(),
            p.account,
            p.token,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        account.transferToken(address(token), recipient, amount, customBps, nonce, deadline, sig);
        _stopPrank();

        assertEq(token.balanceOf(treasury), balBeforeTreasury + feeAmount, "treasury token fee");
        assertEq(token.balanceOf(recipient), balBeforeRecipient + amount, "recipient token amount");
        assertEq(token.balanceOf(address(account)), balBeforeAccount - totalRequired, "account token decreased by total");
    }

    function test_invalid_signer_rejected() public {
        uint256 amount = 1 ether;
        uint256 customBps = 100;

        IFeeManager.FeePermit memory p = IFeeManager.FeePermit({
            account: address(account),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: 777,
            deadline: block.timestamp + 1 hours
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.FEE_PERMIT_TYPEHASH(),
            p.account,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign with wrong key
        uint256 wrongPk = 0xABCDEF;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        _entryPointPrank();
        vm.expectRevert();
        account.transferETH(recipient, amount, customBps, p.nonce, p.deadline, sig);
        _stopPrank();
    }

    function test_tampered_permit_data_rejected() public {
        uint256 amount = 1 ether;
        uint256 customBps = 100;
        IFeeManager.FeePermit memory p = IFeeManager.FeePermit({
            account: address(account),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: 778,
            deadline: block.timestamp + 1 hours
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.FEE_PERMIT_TYPEHASH(),
            p.account,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Call with a different amount (tampered)
        _entryPointPrank();
        vm.expectRevert();
        account.transferETH(recipient, amount + 1, customBps, p.nonce, p.deadline, sig);
        _stopPrank();
    }

    function test_max_fee_cap_enforced() public {
        uint256 amount = 1 ether;
        uint256 overCapBps = 1001; // > 10%

        IFeeManager.FeePermit memory p = IFeeManager.FeePermit({
            account: address(account),
            to: recipient,
            amount: amount,
            feeBps: overCapBps,
            nonce: 779,
            deadline: block.timestamp + 1 hours
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.FEE_PERMIT_TYPEHASH(),
            p.account,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        _entryPointPrank();
        vm.expectRevert();
        account.transferETH(recipient, amount, overCapBps, p.nonce, p.deadline, sig);
        _stopPrank();
    }

    function test_zero_address_recipient_reverts() public {
        uint256 amount = 1 ether;
        _entryPointPrank();
        vm.expectRevert();
        account.transferETH(address(0), amount, 0, 1, block.timestamp + 1, hex"");
        _stopPrank();
    }

    function test_deadline_boundary_now_succeeds() public {
        uint256 amount = 1 ether;
        uint256 customBps = 100;
        IFeeManager.FeePermit memory p = IFeeManager.FeePermit({
            account: address(account),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: 780,
            deadline: block.timestamp // exactly now
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.FEE_PERMIT_TYPEHASH(),
            p.account,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        _entryPointPrank();
        account.transferETH(recipient, amount, customBps, p.nonce, p.deadline, sig);
        _stopPrank();
    }

    function test_treasury_receive_failure_bubbles() public {
        // Set treasury to a reverting receiver
        RevertingReceiver rev = new RevertingReceiver();
        feeManager.updateTreasury(address(rev));

        uint256 amount = 1 ether;
        _entryPointPrank();
        vm.expectRevert();
        account.transferETH(recipient, amount, 0, 2, block.timestamp + 1, hex"");
        _stopPrank();
    }

    function test_token_transfer_failure_bubbles() public {
        // Bad token that reverts on transferFrom
        BadERC20 bad = new BadERC20();
        bad.mint(address(account), 1_000_000 ether);

        // No approve needed: bad.allowance returns MAX so feeManager proceeds to transferFrom and reverts
        uint256 amount = 1000 ether;
        uint256 nonce = 881;
        uint256 deadline = block.timestamp + 1 hours;

        IFeeManager.TokenFeePermit memory p = IFeeManager.TokenFeePermit({
            account: address(account),
            token: address(bad),
            to: recipient,
            amount: amount,
            feeBps: 0,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.TOKEN_FEE_PERMIT_TYPEHASH(),
            p.account,
            p.token,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        _entryPointPrank();
        vm.expectRevert();
        account.transferToken(address(bad), recipient, amount, 0, nonce, deadline, sig);
        _stopPrank();
    }

    function test_direct_call_not_from_entrypoint_reverts() public {
        uint256 amount = 1 ether;
        vm.expectRevert(bytes("not from self or EntryPoint"));
        account.transferETH(recipient, amount, 0, 3, block.timestamp + 1, hex"");
    }

    // ============ Additional token-permit tests ============

    function test_token_permit_invalid_signer_rejected() public {
        uint256 amount = 500 ether;
        uint256 customBps = 100; // 1%
        uint256 nonce = 991;
        uint256 deadline = block.timestamp + 1 hours;

        IFeeManager.TokenFeePermit memory p = IFeeManager.TokenFeePermit({
            account: address(account),
            token: address(token),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.TOKEN_FEE_PERMIT_TYPEHASH(),
            p.account,
            p.token,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        // wrong key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        _entryPointPrank();
        vm.expectRevert();
        account.transferToken(address(token), recipient, amount, customBps, nonce, deadline, sig);
        _stopPrank();
    }

    function test_token_permit_tampered_fields_rejected() public {
        uint256 amount = 400 ether;
        uint256 customBps = 50; // 0.5%
        uint256 nonce = 992;
        uint256 deadline = block.timestamp + 1 hours;

        IFeeManager.TokenFeePermit memory p = IFeeManager.TokenFeePermit({
            account: address(account),
            token: address(token),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.TOKEN_FEE_PERMIT_TYPEHASH(),
            p.account,
            p.token,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Tamper amount
        _entryPointPrank();
        vm.expectRevert();
        account.transferToken(address(token), recipient, amount + 1, customBps, nonce, deadline, sig);
        _stopPrank();
    }

    function test_token_permit_expired_reverts() public {
        uint256 amount = 300 ether;
        uint256 customBps = 75; // 0.75%
        uint256 nonce = 993;
        uint256 deadline = block.timestamp - 1; // expired

        IFeeManager.TokenFeePermit memory p = IFeeManager.TokenFeePermit({
            account: address(account),
            token: address(token),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.TOKEN_FEE_PERMIT_TYPEHASH(),
            p.account,
            p.token,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        _entryPointPrank();
        vm.expectRevert();
        account.transferToken(address(token), recipient, amount, customBps, nonce, deadline, sig);
        _stopPrank();
    }

    function test_token_permit_nonce_replay_reverts() public {
        uint256 amount = 200 ether;
        uint256 customBps = 25; // 0.25%
        uint256 nonce = 994;
        uint256 deadline = block.timestamp + 1 hours;

        // Approve enough for totalRequired once
        uint256 feeAmount = (amount * customBps) / 10000;
        uint256 totalRequired = amount + feeAmount;
        _entryPointPrank();
        bytes memory approveData = abi.encodeWithSelector(IERC20Minimal.approve.selector, address(feeManager), totalRequired);
        account.execute(address(token), 0, approveData);
        _stopPrank();

        IFeeManager.TokenFeePermit memory p = IFeeManager.TokenFeePermit({
            account: address(account),
            token: address(token),
            to: recipient,
            amount: amount,
            feeBps: customBps,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 domainSeparator = feeManager.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(
            feeManager.TOKEN_FEE_PERMIT_TYPEHASH(),
            p.account,
            p.token,
            p.to,
            p.amount,
            p.feeBps,
            p.nonce,
            p.deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FEE_SIGNER_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // First call succeeds
        _entryPointPrank();
        account.transferToken(address(token), recipient, amount, customBps, nonce, deadline, sig);
        _stopPrank();

        // Replay should revert
        _entryPointPrank();
        vm.expectRevert();
        account.transferToken(address(token), recipient, amount, customBps, nonce, deadline, sig);
        _stopPrank();
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("nope");
    }
}

contract BadERC20 {
    mapping(address => uint256) public balanceOf;
    string public name = "BadToken";
    string public symbol = "BAD";
    uint8 public decimals = 18;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function allowance(address, address) external pure returns (uint256) { return type(uint256).max; }
    function approve(address, uint256) external pure returns (bool) { return true; }
    function transfer(address, uint256) external pure returns (bool) { return true; }
    function transferFrom(address, address, uint256) external pure returns (bool) { revert("bad transfer"); }
}


