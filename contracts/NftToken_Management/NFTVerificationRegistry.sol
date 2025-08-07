// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract NFTVerificationRegistry is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum AssetType {
        ERC721,
        ERC1155
    }

    struct NFTInfo {
        address contractAddress;
        uint256 tokenId;
        address owner;
        string metadataUri;
        bytes32 metadataHash;
        AssetType AssetType;
        bool isRegistered;
        bool isVerified;
        uint256 registerTime;
        uint256 lastUpdateTime;
        uint256 verificationTime;
    }

    //blacklist Prohibited NFT addresses for registration
    mapping(address => bool) public blacklistedContract;
    //contractId + tokenId => NFTinfo
    mapping(bytes32 => NFTInfo) public nftRegistry;
    // NFT address => NFT Account
    mapping(address => uint256) public registeredCount;

    event NFTRegistered(
        address indexed contractAddress,
        uint256 indexed tokenId,
        address indexed owner,
        AssetType AssetType,
        string metadataUri,
        bytes32 metadataHash
    );

    event NFTVerified(
        address indexed contractAddress,
        uint256 indexed tokenId,
        address indexed verifier
    );

    event NFTOwnerUpdated(
        address indexed contractAddress,
        address indexed tokenId,
        address indexed oldOwner,
        address newOwner
    );

    event NFTMetadataUpdate(
        address indexed contractAddress,
        uint256 indexed tokenId,
        string oldMatedataUri,
        string newMateDateUri,
        bytes32 oldMatedataHash,
        bytes32 newMatedataHash
    );

    event ContractBlackList(address indexed contractAddress);
    event ContractWriteList(address indexed contractAddress);
    //Mark the completion of batch registration and count the number of registrations.
    event BatchRegistrationComplate(
        address indexed register,
        uint256 count,
        uint256 timestamp
    );

    //init && Grant deployment to all these roles
    function initialize() external initializer {
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    modifier onlyVerifier() {
        require(hasRole(VERIFIER_ROLE, msg.sender), "not a verifier");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "not a operator");
        _;
    }

    /**
     * Returns a unique identifier for an NFT based on its contract address and token ID.
     * @param contractAddress The address of the NFT contract.
     * @param tokenId The token ID of the NFT.
     */
    function _getNFTKey(
        address contractAddress,
        uint256 tokenId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractAddress, tokenId));
    }

    /**
     * Computes the hash of the metadata URL.
     * @param metadataUri The URL of the NFT metadata to be hashed.
     */
    function _computeMetadataHash(
        string calldata metadataUri
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(metadataUri));
    }

    function BatchRegistrationERC721(
        address contractAddress,
        uint256[] calldata tokenIds,
        string[] calldata metadataUris
    ) external whenNotPaused nonReentrant {
        require(contractAddress != address(0), "Invaild contract address");
        require(!blacklistedContract[contractAddress], "contract is blacklist");
        require(
            tokenIds.length != 0 && tokenIds.length == metadataUris.length,
            "Invalid input lengths"
        );
        require(
            IERC165(contractAddress).supportsInterface(
                type(IERC721).interfaceId
            ),
            "Not ERC721"
        );
        IERC721 nftContract = IERC721(contractAddress);
        uint256 registered = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            bytes32 nftKey = _getNFTKey(contractAddress, tokenId);

            if (nftRegistry[nftKey].isRegistered) continue;

            address NFTowner = nftContract.ownerOf(tokenId);
            require(NFTowner != address(0), " NFT does not exist");

            nftRegistry[nftKey] = NFTInfo({
                contractAddress: contractAddress,
                tokenId: tokenId,
                owner: NFTowner,
                metadataUri: metadataUris[i],
                metadataHash: _computeMetadataHash(metadataUris[i]),
                AssetType: AssetType.ERC721,
                isRegistered: true,
                isVerified: false,
                registerTime: block.timestamp,
                lastUpdateTime: block.timestamp,
                verificationTime: 0
            });

            registeredCount[contractAddress]++;
            registered++;

            emit NFTRegistered(
                contractAddress,
                tokenId,
                NFTowner,
                AssetType.ERC721,
                metadataUris[i],
                _computeMetadataHash(metadataUris[i])
            );
        }

        emit BatchRegistrationComplate(msg.sender, registered, block.timestamp);
    }

    function BatchRegistrationERC1155(
        address contractAddress,
        uint256[] calldata tokenIds,
        string[] calldata metadataUris
    ) external whenNotPaused nonReentrant {
        require(contractAddress != address(0), "Invaild contract address");
        require(!blacklistedContract[contractAddress], "contract is blacklist");
        require(
            tokenIds.length != 0 && tokenIds.length == metadataUris.length,
            "Invalid input lengths"
        );
        require(
            IERC165(contractAddress).supportsInterface(
                type(IERC1155).interfaceId
            ),
            "Not ERC721"
        );
        IERC1155 nftContract = IERC1155(contractAddress);
        uint256 registered = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            bytes32 nftKey = _getNFTKey(contractAddress, tokenId);

            if (nftRegistry[nftKey].isRegistered) continue;

            require(
                nftContract.balanceOf(msg.sender, tokenId) > 0,
                "Caller does not own NFT"
            );

            nftRegistry[nftKey] = NFTInfo({
                contractAddress: contractAddress,
                tokenId: tokenId,
                owner: msg.sender,
                metadataUri: metadataUris[i],
                metadataHash: _computeMetadataHash(metadataUris[i]),
                AssetType: AssetType.ERC721,
                isRegistered: true,
                isVerified: false,
                registerTime: block.timestamp,
                lastUpdateTime: block.timestamp,
                verificationTime: 0
            });

            registeredCount[contractAddress]++;
            registered++;

            emit NFTRegistered(
                contractAddress,
                tokenId,
                msg.sender,
                AssetType.ERC1155,
                metadataUris[i],
                _computeMetadataHash(metadataUris[i])
            );
        }

        emit BatchRegistrationComplate(msg.sender, registered, block.timestamp);
    }

    function registrationERC721(
        address contractAddress,
        uint256 tokenId,
        string calldata metadataUri
    ) external whenNotPaused nonReentrant {
        require(contractAddress != address(0), "Invaild contract address");
        require(!blacklistedContract[contractAddress], "contract is blacklist");
        require(tokenId > 0, "Invalid token ID");
        require(
            IERC165(contractAddress).supportsInterface(
                type(IERC721).interfaceId
            ),
            "Not ERC721"
        );
        IERC721 nftContract = IERC721(contractAddress);

        bytes32 nftKey = _getNFTKey(contractAddress, tokenId);

        require(!nftRegistry[nftKey].isRegistered, "NFT already registered");

        address NFTowner = nftContract.ownerOf(tokenId);
        require(NFTowner != address(0), " NFT does not exist");

        nftRegistry[nftKey] = NFTInfo({
            contractAddress: contractAddress,
            tokenId: tokenId,
            owner: NFTowner,
            metadataUri: metadataUri,
            metadataHash: _computeMetadataHash(metadataUri),
            AssetType: AssetType.ERC721,
            isRegistered: true,
            isVerified: false,
            registerTime: block.timestamp,
            lastUpdateTime: block.timestamp,
            verificationTime: 0
        });

        registeredCount[contractAddress]++;

        emit NFTRegistered(
            contractAddress,
            tokenId,
            NFTowner,
            AssetType.ERC721,
            metadataUri,
            _computeMetadataHash(metadataUri)
        );
    }

     function registrationERC1155(
        address contractAddress,
        uint256 tokenId,
        string calldata metadataUri
    ) external whenNotPaused nonReentrant {
        require(contractAddress != address(0), "Invaild contract address");
        require(!blacklistedContract[contractAddress], "contract is blacklist");
        require(tokenId > 0, "Invalid token ID");
        require(
            IERC165(contractAddress).supportsInterface(
                type(IERC1155).interfaceId
            ),
            "Not ERC721"
        );
        IERC1155 nftContract = IERC1155(contractAddress);

        bytes32 nftKey = _getNFTKey(contractAddress, tokenId);

        require(!nftRegistry[nftKey].isRegistered, "NFT already registered");

        require(nftContract.balanceOf(msg.sender, tokenId)>0,"Caller does not own NFT");

        nftRegistry[nftKey] = NFTInfo({
            contractAddress: contractAddress,
            tokenId: tokenId,
            owner: msg.sender,
            metadataUri: metadataUri,
            metadataHash: _computeMetadataHash(metadataUri),
            AssetType: AssetType.ERC1155,
            isRegistered: true,
            isVerified: false,
            registerTime: block.timestamp,
            lastUpdateTime: block.timestamp,
            verificationTime: 0
        });

        registeredCount[contractAddress]++;

        emit NFTRegistered(
            contractAddress,
            tokenId,
            msg.sender,
            AssetType.ERC1155,
            metadataUri,
            _computeMetadataHash(metadataUri)
        );
    }

    function verifyNFT(
        address contractAddress,
        uint256 tokenId
    ) external whenNotPaused onlyVerifier nonReentrant {
        bytes32 nftKey = _getNFTKey(contractAddress,tokenId);
        NFTInfo storage nftInfo = nftRegistry[nftKey];
        require(nftInfo.isRegistered,"NFT NO REGISTERED");
        require(!nftInfo.isVerified, "NFT already verified");

        nftInfo.isVerified = true;
        nftInfo.verificationTime = block.timestamp;
        nftInfo.lastUpdateTime = block.timestamp;

        emit NFTVerified(contractAddress,tokenId,msg.sender);
    }

    function batchUpdateOwners(
        address contractAddress,
        uint256[] calldata tokenIds,
        address[] calldata newOwners
    )external whenNotPaused onlyOperator nonReentrant{
        require(contractAddress!=address(0),"Invaild NFT address");
        require(tokenIds.length == newOwners.length,"Input length mismatch");

        for(uint256 i;i<tokenIds.length;i++){
              //_updateOwner(contractAddress, tokenIds[i], newOwners[i]);
        }
    }
}
