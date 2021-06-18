enum OpKind {
    Render = 0,
    SetFragment = 1,
    SetFragmentRootTemplate = 2,
    PatchFragment = 3,
    SetTemplate = 4,
    Reset = 5,
}

export default class JSONEncoding {
    fragments: {[key: number]: any} = {};
    templates: {[key: number]: any} = {};

    out: any = null;

    constructor() {}

    handleMessage(ops: any): boolean {
        let rendered = false;

        ops.forEach((op: any) => {
            let kind: OpKind = op[0];
            switch (kind) {
                case OpKind.Render:
                    this.out = this.renderFragment(op[1]);
                    rendered = true;
                    break;
                case OpKind.SetFragment:
                    this.fragments[op[1]] = op[2];
                    break;
                case OpKind.SetFragmentRootTemplate:
                    this.fragments[op[1]] = ["$t", op[2]].concat(op.slice(3));
                    break;
                case OpKind.PatchFragment:
                    throw "unimpl";
                    break;
                case OpKind.SetTemplate:
                    this.templates[op[1]] = op[2];
                    break;
            }
        });

        return rendered;
    }

    renderFragment(fragmentId: number): any {
        let body = this.fragments[fragmentId];
        return this.renderBody(body);
    }

    renderTemplate(templateId: number, slots: Array<any>) {
        let body = this.templates[templateId];
        return this.renderBody(body, slots);
    }

    renderBody(body: any, templateSlots: Array<any> | null = null): any {
        if (body === null) {
            return null;
        }
        if (Array.isArray(body)) {
            if (body[0] == "$r") {
                return this.renderFragment(body[1]);
            } else if (body[0] == "$t") {
                let innerSlots = body.slice(2)
                    .map((slot: any) => this.renderBody(slot, templateSlots));
                return this.renderTemplate(body[1], innerSlots);
            } else if (body[0] == "$s") {
                return templateSlots[body[1]];
            } else if (body[0] == "$e") {
                return body[1];
            } else {
                return body.map((item: any) => this.renderBody(item, templateSlots));
            }
        }
        if (typeof body == 'object') {
            let out = {};
            for (const [key, val] of Object.entries(body)) {
                out[key] = this.renderBody(val, templateSlots);
            }
            return out;
        }
        if (typeof body == 'string') {
            return body;
        }
        if (typeof body == 'number') {
            return body;
        }
        if (body === true || body == false) {
            return body;
        }
        throw "unimpl";
    }

};
