public with sharing class NeuraFormUtils {
    private static String namespacePrefix;

    public static String getNamespacePrefix() {
        if (namespacePrefix == null) {
            String[] parts = String.valueOf(NeuraFormUtils.class).split('\\.', 2);
            namespacePrefix = (parts.size() == 2 ? parts[0] + '__' : '');
        }
        return namespacePrefix;
    }
}