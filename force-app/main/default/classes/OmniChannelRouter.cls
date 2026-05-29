public without sharing class OmniChannelRouter implements Queueable {

    private List<Id> caseIds;

    public OmniChannelRouter(List<Id> caseIds) {
        this.caseIds = caseIds;
    }

    public void execute(QueueableContext ctx) {

        // Get the Case service channel ID
        List<ServiceChannel> channels = [
            SELECT Id FROM ServiceChannel 
            WHERE RelatedEntity = 'Case' 
            LIMIT 1
        ];

        if (channels.isEmpty()) {
            return;
        }

        Id channelId = channels[0].Id;

        // Query cases that are owned by queues
        List<Case> queueCases = [
            SELECT Id, OwnerId 
            FROM Case 
            WHERE Id IN :caseIds 
            AND Owner.Type = 'Queue'
        ];

        if (queueCases.isEmpty()) {
            return;
        }

        // Find available agents in those queues
        Set<Id> queueIds = new Set<Id>();
        for (Case c : queueCases) {
            queueIds.add(c.OwnerId);
        }

        // Get queue members
        Map<Id, Set<Id>> queueToMembers = new Map<Id, Set<Id>>();
        for (GroupMember gm : [
            SELECT GroupId, UserOrGroupId 
            FROM GroupMember 
            WHERE GroupId IN :queueIds
        ]) {
            if (!queueToMembers.containsKey(gm.GroupId)) {
                queueToMembers.put(gm.GroupId, new Set<Id>());
            }
            queueToMembers.get(gm.GroupId).add(gm.UserOrGroupId);
        }

        // Find online agents
        Map<Id, UserServicePresence> onlineAgents = new Map<Id, UserServicePresence>();
        for (UserServicePresence usp : [
            SELECT UserId, ConfiguredCapacity 
            FROM UserServicePresence 
            WHERE IsCurrentState = true 
            AND IsAway = false
        ]) {
            onlineAgents.put(usp.UserId, usp);
        }

        // Check existing AgentWork to avoid duplicates
        Set<Id> alreadyRouted = new Set<Id>();
        for (AgentWork aw : [
            SELECT WorkItemId 
            FROM AgentWork 
            WHERE WorkItemId IN :caseIds 
            AND Status != 'Closed'
        ]) {
            alreadyRouted.add(aw.WorkItemId);
        }

        // Create AgentWork for each case — route to an available agent in the queue
        List<AgentWork> workItems = new List<AgentWork>();

        for (Case c : queueCases) {
            if (alreadyRouted.contains(c.Id)) {
                continue;
            }

            Set<Id> members = queueToMembers.get(c.OwnerId);
            if (members == null) {
                continue;
            }

            // Find first available agent who is a member of this queue
            for (Id memberId : members) {
                if (onlineAgents.containsKey(memberId)) {
                    AgentWork aw = new AgentWork();
                    aw.WorkItemId = c.Id;
                    aw.UserId = memberId;
                    aw.ServiceChannelId = channelId;
                    workItems.add(aw);
                    break;
                }
            }
        }

        if (!workItems.isEmpty()) {
            try {
                insert workItems;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'OmniChannelRouter failed: ' + e.getMessage());
            }
        }
    }
}