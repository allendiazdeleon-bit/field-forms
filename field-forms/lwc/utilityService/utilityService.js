const generateUUID = () => {
    return 'UUID' + Date.now().toString(36) + Math.random().toString(36).substr(2);
};

// Other utility functions can be added here

export { generateUUID };