// neuraFormStore.js
let listeners = [];
let data = {
    builderFormFactor: 'desktop-view',
    viaBuilder: false
};

const notifyListeners = () => {
    listeners.forEach(listener => listener(data));
};

export const store = {
    subscribe(listener) {
        listeners.push(listener);
        return () => {
            listeners = listeners.filter(l => l !== listener);
        };
    },
    setBuilderFormFactor(formFactor) {
        data.builderFormFactor = formFactor;
        notifyListeners();
    },
    setAllQuestions(questions){
        data.allQuestions = questions;
        notifyListeners();
    },
    setAllConfig(config){
        data.allConfig = config;
        notifyListeners();
    },
    setViaBuilder(via) {
        data.viaBuilder = via;
        notifyListeners();
    },
    getState() {
        return data;
    }
};