//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/** @dev The following libraries were found here https://github.com/ConsenSys/ethereum-developer-tools-list
*/
import "./Ownable.sol";
import "./BokkyPooBahsDateTimeLibrary.sol";
import "./SafeMath.sol";
 
contract Resume is Ownable {

    // Specify that this contract uses SafeMath library for operations involving uint
    using SafeMath for uint;
  
    // Specify that this contract uses BokkyPooBahsDateTimeLibrary for operations involving uint
    using BokkyPooBahsDateTimeLibrary for uint;
   
    /* set owner */
    address public _owner;
    
    // build in the Circuit Breaker / Pause Contract Functionality
    bool private emergency_stop;

    /* keep track of the users, institutions, and entries */
    uint private UserCount;
    uint private InstitutionCount;
    uint private EntryCount;

    /* keep a list of Admins that can add universities, users, entries */
    mapping(address => bool) private admins;

    /* keep a list of valid users */
    mapping(address => bool) userList;
    
    /* Creating a public mapping that maps the user address to the user ID. */
    mapping (address => uint) userIDMaps;
    
    /* Creating a public mapping that maps the UserID (a number) to a User. */
    mapping (uint => User) public users;

    struct User {
        string name;
        uint date_joined;
        address userAddr;
    }

    /* keep a list of valid institutions */
    mapping(address => bool) institutionList;
    
    /* Creating a public mapping that maps the institution address to the institution ID. */
    mapping (address => uint) institutionIDMaps;
    
    /* Creating a public mapping that maps the InstitutionID (a number) to an Instituion. */
    mapping (uint => Institution) public institutions;

    /* Creating an enum called institutionType for types of institutions */
    enum institutionType {University, School, Certificator}

    struct Institution {
        string name;
        uint date_joined;
        institutionType itype;
        address institutionAddr;
    }

    /* Creating a public mapping that maps the UserID (a number) to a resume.
    Each user is mapped to one resume, and joined using UserID
    There is also a resume_queue for each user of entries that have yet to
    be approved by the user. 
    */
    mapping (uint => uint[]) public resumes;
    mapping (uint => uint[]) public resume_queues;
    
    /* This maps user id to entry id in a user queue so we can check if an entry
    exists in a user queue*/
    mapping (uint => uint) private queueMaps;


    uint[] the_resume;
    uint[] resume_queue;

    mapping (uint => Entry) entries;
  
    enum entryType {Degree, Certificate}
    
    struct Entry {
        address recipient;
        bool approved;
        string entry_title;
        string degree_descr;
        uint institutionID;
        uint date_received;
        entryType etype;
        string review;
    }

    event AddedAdmin(address adminAddr);
    event CircuitBreak(bool emergency_stopped);
    event AddedInstitution(uint UniversityID);
    event AddedUser(uint UserID);
    event EntryCreated(uint EntryID);
    event AddedtoQueue(uint EntryID, uint UserID);
    event AddedtoResume(uint EntryID, uint UserID);
    event EntryRejected(uint EntryID, uint UserID);
    
    /* This check to see if caller is the owner. Inherited from ownable contract*/
    modifier onlyOwner() override virtual {
        require(isOwner(), "This action is prohibited for non Owner.");
        _;
    }

    modifier contractActive() {
        require(emergency_stop==false, "Contract is no longer active. Please contact owner.");
        _;
    }

    modifier verifyAdmin () 
      { 
        require (admins[msg.sender]==true, "This action is prohibited for non Admins.");
        _;
    }
    
    modifier verifyUser () 
      { 
        require (userList[msg.sender]==true, "Not a valid User.");
        _;
    }

    modifier verifyInstitution () 
      { 
        require (institutionList[msg.sender]==true, "Not a valid Institution.");
        _;
    }

    modifier verifyCaller (address _address) 
      { 
        require (msg.sender == _address, "Message sender is not correct.");
        _;
    }

    modifier verifyViewUserResume (uint _UserID) 
      { 
        require (userList[users[_UserID].userAddr]==true, "This ID is not a valid user.");
        _;
    }

    modifier verifyUserEntry (address _address) 
      { 
        require (userList[_address]==true, "Cannot add entry to this user.");
        _;
    }

    modifier verifyQueueEmpty (address _address) 
      { 
        uint queue_length= resume_queues[userIDMaps[_address]].length;
        require (queue_length>0, "There are no entries in your queue.");
        _;
    }

    modifier verifyResumeEmpty (uint _UserID) 
      { 
        uint _resumeLength = resumes[_UserID].length;
        require (_resumeLength>0, "There are no entries in this user's resume.");
        _;
    }

    modifier verifyResumeEntryExists (uint _UserID, uint _entryElement) 
      { 
        uint _resumeLength= resumes[_UserID].length;
        require (_entryElement<_resumeLength, "This entry element does not exist for this user.");
        _;
    }

    modifier verifyApproved (uint _UserID, uint _entryElement)
      {
        
        require(entries[resumes[_UserID][_entryElement]].approved==true, "This entry has not been approved for viewing");
        _;
    }

    modifier verifyUserApproval (uint _UserID)
      { 
        require (_UserID==userIDMaps[msg.sender], "This entry is not assigned to you.");
        _;
    }

    modifier verifyNextEntryUp (uint _EntryID)
      { 
        require (_EntryID==resume_queues[userIDMaps[msg.sender]][0],
            "This entry is not the next one in your queue.");
        _;
    }

    /** @dev This is the constructor
    We are setting the owner to the one who starts this contract
    Sets the owner as the first admin
    UserCount, InstitutionCount, and EntryCount set to 1 since we start IDs at 1 */
    constructor() payable  {
        _owner = msg.sender;
        emergency_stop = false;
        admins[_owner] = true;
        UserCount = 1;
        InstitutionCount = 1;
        EntryCount = 1;
    }

    /** @dev This function lets the owner of the contract add admins to manage the contract 
    @param admin is the address of the admin to add
    @return true
    */
    function addAdmin(address admin)
    public
    contractActive()
    onlyOwner()
    returns(bool)
    {
        admins[admin] = true;
        emit AddedAdmin(admin);
        return true;
    }

    /** @dev This function lets the owner of the contract change the contract state from 
     active to non-active and vice versa 
    @param _emergency_stop is a bool that specifies whether it is an emergency
    @return true
    */
    function circuitBreakContract(bool _emergency_stop)
    public
    onlyOwner()
    returns(bool)
    {
        emergency_stop = _emergency_stop;
        emit CircuitBreak(_emergency_stop);
        return true;
    }

    /** @dev This function let's users sign up for this service to record their resumes
    @param _name is a value for name of the user to enter
    @return true
    */
    function signUpUser(string memory _name)
    public
    payable
    contractActive()
    returns(bool)
    {
        users[UserCount] = User({name: _name, date_joined: block.timestamp, userAddr: msg.sender});
        userIDMaps[msg.sender] = UserCount;
        userList[msg.sender] = true;
        emit AddedUser(UserCount);
        UserCount = UserCount + 1;
        return true;
    }

     /** @dev This function let's admins add institutions that are legitimate, allowing them submit
    entries for users on the platform
    @param _name characteristics of the institution
    @param _institutionAddr characteristics of the institution
    @param _itype characteristics of the institution
    @return true
    */
    function addInstitution(string memory _name, address _institutionAddr, institutionType _itype) 
    public
    contractActive()
    verifyAdmin()
    returns(bool)
    {
        institutionIDMaps[_institutionAddr] = InstitutionCount;
        institutions[InstitutionCount] = Institution({name: _name, date_joined: block.timestamp, itype: _itype, institutionAddr: _institutionAddr});
        institutionList[_institutionAddr] = true;
        emit AddedInstitution(InstitutionCount);
        InstitutionCount = InstitutionCount + 1;
        return true;
    }

    /** @dev This function let's institutions add entries that can go on the resumes of users
    @param _recipient characteristics of the entry
    @param _entry_title characteristics of the entry
    @param _degree_descr characteristics of the entry
    @param _etype characteristics of the entry
    @param _review characteristics of the entry
    @return true
    */
    function addEntry(address _recipient, string memory _entry_title, string memory _degree_descr, 
       entryType _etype, string memory _review) 
    public
    contractActive()
    verifyInstitution()
    verifyUserEntry(_recipient)
    returns(bool)
    {
        bool _approved = false;
        uint _institutionID = institutionIDMaps[msg.sender];
        uint _date_received = block.timestamp;
        entries[EntryCount] = Entry({recipient: _recipient, approved: _approved,
            entry_title: _entry_title, degree_descr: _degree_descr, institutionID: _institutionID,
            date_received: _date_received, etype: _etype, review: _review});
        emit EntryCreated(EntryCount);

        uint _UserID = userIDMaps[_recipient];
        resume_queues[_UserID].push(EntryCount);
        queueMaps[EntryCount] = _UserID;
        emit AddedtoQueue(EntryCount, _UserID);

        EntryCount = EntryCount + 1;
        return true;
    }

    /** @dev This function let's users approve entries in their resume queue
    Once the entry is approved, it moves from resume queue to the offical resume
    If it rejected, then we just remove it from the queue.
    This requires user to enter in the that the entry they are trying to edit
    is the next entry up in their queue so they are aware which one they are approving
    or rejecting.
    @param _entryID universal entry ID of the entry to approve or reject 
    @param _doYouWantToApprove choie of user to approve or reject 
    @return true
    */
    function approveEntry(uint _entryID, bool _doYouWantToApprove)
    public
    contractActive()
    verifyUserApproval(queueMaps[_entryID])
    verifyQueueEmpty(msg.sender)
    verifyNextEntryUp (_entryID)
    returns(bool)
    {
        uint _nextEntryID = resume_queues[userIDMaps[msg.sender]][0];
        uint _length = resume_queues[userIDMaps[msg.sender]].length;
        for (uint i = 0; i < (_length - 1); i++) 
        {
            resume_queues[userIDMaps[msg.sender]][i] = resume_queues[userIDMaps[msg.sender]][i+1];
        }
        delete resume_queues[userIDMaps[msg.sender]][_length-1];
        resume_queues[userIDMaps[msg.sender]].pop();
   
        if (_doYouWantToApprove==true)
        {
            entries[_nextEntryID].approved = true;
            resumes[userIDMaps[msg.sender]].push(_nextEntryID);
            emit AddedtoResume(_entryID, userIDMaps[msg.sender]);
        }
        else
        {
            emit EntryRejected(_entryID, userIDMaps[msg.sender]);
        }
        return true;
    }

    function showMyResumeQueue()
      public 
      view
      contractActive()
      verifyUser()
      verifyQueueEmpty(msg.sender)
      returns (uint entryID, string memory entry_title, string memory degree_descr,
      string memory institution_name, uint date_received, string memory review) 
      {
        uint _latestID = resume_queues[userIDMaps[msg.sender]][0];
        entryID = _latestID;
        entry_title = entries[_latestID].entry_title;
        degree_descr = entries[_latestID].degree_descr;
        institution_name = institutions[entries[_latestID].institutionID].name;
        date_received = entries[_latestID].date_received;
        review = entries[_latestID].review;
        return (entryID, entry_title, degree_descr, institution_name, date_received, review);
      }


    function viewResume(uint _UserID, uint _entryElement)
      public 
      view
      contractActive()
      verifyViewUserResume (_UserID)
      verifyResumeEmpty (_UserID)
      verifyResumeEntryExists (_UserID, _entryElement)
      returns (uint entryID 
      ,string memory entry_title 
      ,string memory degree_descr
      ,string memory institution_name 
      ,uint date_received 
      ,string memory review
      )
    {
        entryID = resumes[_UserID][_entryElement];
        entry_title = entries[entryID].entry_title;
        degree_descr = entries[entryID].degree_descr;
        institution_name = institutions[entries[entryID].institutionID].name;
        date_received = entries[entryID].date_received;
        review=entries[entryID].review;
        return (
        entryID
        , entry_title
        , degree_descr
        , institution_name
        , date_received
        , review
        );
    }

    function checkQueueSize()
      public
      view 
      contractActive()
      verifyUser()
      verifyQueueEmpty(msg.sender)
      returns (uint _queueSize)
    {
        return (resume_queues[userIDMaps[msg.sender]].length);
    }
 
    function checkResumeSize(uint _UserID)
      public
      view 
      contractActive()
      verifyViewUserResume (_UserID)
      verifyResumeEmpty (_UserID)
      returns (uint _resumeSize)
    {
        return (resumes[_UserID].length);
    }  
    
    /** @dev This function let's the owner check who is an admin
    @param _adminAddr is the ID for the admin that the owner wants to check
    @return true of false
    */
    function isAdmin(address _adminAddr)
      public
      view 
      contractActive()
      onlyOwner()
      returns (bool) 
    {
        return (admins[_adminAddr]);
    }

 
    function checkUserID()
      public
      view 
      contractActive()
      verifyUser()
      returns (uint _UserID)
    {
        return (userIDMaps[msg.sender]);
    } 
       /** @dev This function displays owner
    @return address of the owner of the contract
    */
    function showOwner()
      public
      view 
      contractActive()
      returns (address)
    {
        return (_owner);
    }

}
