import JSONEncoding from './encoding/json';

console.log("yay");

type PhxSocket = any;
type PhxSocketCtor = new (url: String, opts: {}) => PhxSocket;
type PhxChannel = any;
type PhxPush = any;

export class Socket {
    socket: PhxSocket;
    opts: {};

    dvCounter: number = 0;

    constructor(url: String, phxSocket: PhxSocketCtor, opts: {} = {}) {
        this.socket = new phxSocket(url, opts);
        this.opts = opts;
    }

    connect() {
        this.socket.connect();
    }

    dataView(route: String, initialParams: {}, opts: {} = {}): LiveData {
        return new LiveData(route, initialParams, opts, this);
    }

    nextDvCounter(): number {
        this.dvCounter += 1;
        return this.dvCounter;
    }

};

class EventBus<Args extends Array<any>> {
    nextId: number = 0;
    listeners: Map<number, (...args: Args) => void> = new Map();

    constructor() {}

    add(listener: (...args: Args) => void): number {
        let id = this.nextId;
        this.nextId += 1;
        this.listeners.set(id, listener);
        return id;
    }

    remove(id: number): boolean {
        return this.listeners.delete(id);
    }

    call(...args: Args) {
        this.listeners.forEach(listener => listener(...args));
    }
}

export enum RejoinPolicy {
    Once,
    Persist,
};

enum LiveDataState {
    ChannelJoining = "channel_joining",
    Joining = "joining",
    Active = "active",
    Terminal = "terminal",
};

export class LiveData {
    rejoinPolicy: RejoinPolicy;

    socket: Socket;

    channel: PhxChannel;
    joinPush: PhxPush;

    onState: EventBus<[LiveDataState]> = new EventBus();
    _state: LiveDataState = LiveDataState.ChannelJoining;
    set state(state: LiveDataState) {
        this._state = state;
        this.onState.call(this._state);
    }
    get state(): LiveDataState {
        return this._state;
    }

    onData: EventBus<[any]> = new EventBus();
    get data(): any {
        return this.encoding.out;
    }

    encoding: JSONEncoding;

    constructor(route: String, initialParams: {}, opts: {}, socket: Socket) {
        this.rejoinPolicy = opts["rejoinPolicy"] || RejoinPolicy.Persist;

        this.socket = socket;

        this.encoding = new JSONEncoding();

        let topic = "dv:c:" + this.socket.nextDvCounter();
        this.channel = this.socket.socket.channel(topic, {"r": [route, initialParams]});

        this.channel.onError(() => {});
        this.channel.onClose(() => {});

        this.channel.on("o", (payload: {}) => {
            console.log(payload);

            let rendered = this.encoding.handleMessage(payload["o"]);

            if (this.state == LiveDataState.ChannelJoining) {
                this.state = LiveDataState.Active;
            }

            if (rendered) {
                this.onData.call(this.data);
            }
        });

        this.joinChannel();
    }

    joinChannel() {
        this.joinPush = this.channel.join();
        this.joinPush.receive("ok", ({messages}) => {
            this.state = LiveDataState.ChannelJoining;
        });
        this.joinPush.receive("error", ({reason}) => {
            this.state = LiveDataState.Terminal;
        });
        this.joinPush.receive("timeout", () => {
            this.state = LiveDataState.ChannelJoining;
        });
    }

    pushEvent(data: any) {
        return this.channel.push("e", {d: data});
    }

};
