public class NeuraFileWrapper {
	@AuraEnabled
    public String linkedEntityId { get; set; }
    @AuraEnabled
    public List<Object> filesData { get; set; }
}