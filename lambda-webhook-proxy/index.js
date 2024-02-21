const crypto = require('crypto');

import { CodePipelineClient, StartPipelineExecutionCommand } from "@aws-sdk/client-codepipeline";

function signRequestBody(key, body) {
    return `sha256=${crypto.createHmac('sha256', key).update(body, 'utf-8').digest('hex')}`;
}

exports.githubWebhookListener = async (event, context, callback) => {
    let errMsg; // eslint-disable-line

    const headers = event.headers;
    const body = JSON.parse(event.body)

    const token = process.env.GITHUB_WEBHOOK_SECRET;
    if (typeof token !== 'string') {
        errMsg = 'Must provide a \'GITHUB_WEBHOOK_SECRET\' env variable';
        return callback(null, {
            statusCode: 401,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    const targetGithubRepositoryBranch = process.env.TARGET_GITHUB_REPOSITORY_BRANCH;
    if (typeof targetGithubRepositoryBranch !== 'string') {
        errMsg = 'Must provide a \'TARGET_GITHUB_REPOSITORY_BRANCH\' env variable';
        return callback(null, {
            statusCode: 401,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    if (`refs/heads/${targetGithubRepositoryBranch}` !== body.ref) {
        errMsg = `Ref ${body.ref} is not equal to refs/heads/${targetGithubRepositoryBranch}`
        return callback(null, {
            statusCode: 401,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    const sig = headers['X-Hub-Signature-256'];
    if (!sig) {
        errMsg = 'No X-Hub-Signature found on request';
        return callback(null, {
            statusCode: 401,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    const githubEvent = headers['X-GitHub-Event'];
    if (!githubEvent) {
        errMsg = 'No X-Github-Event found on request';
        return callback(null, {
            statusCode: 422,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    const id = headers['X-GitHub-Delivery'];
    if (!id) {
        errMsg = 'No X-Github-Delivery found on request';
        return callback(null, {
            statusCode: 401,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    const calculatedSig = signRequestBody(token, event.body);
    if (sig !== calculatedSig) {
        errMsg = `X-Hub-Signature incorrect. Github webhook token doesn\'t match`;
        return callback(null, {
            statusCode: 401,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    delete headers['Host']
    delete headers['Accept']

    if (headers['X-GitHub-Event'] !== 'push') {
        errMsg = 'Only push X-GitHub-Event is allowed';

        return callback(null, {
            statusCode: 401,
            headers: { 'Content-Type': 'text/plain' },
            body: errMsg,
        });
    }

    const pipeline_name_regexp_pair = Object.entries(process.env).reduce((acc, pair) => {
        const [key, targetPipelineName] = pair
        if (!key.startsWith('TARGET_PIPELINE_NAME')) {
            return acc
        }
        const tokens = key.split('_')
        // This environment variable follows pattern TARGET_PIPELINE_NAME_${index} so last token is an index
        const index = tokens[tokens.length-1]
        const regexp = process.env[`TARGET_PIPELINE_REGEXP_${index}`]
        if (!regexp || !targetPipelineName) {
            throw new Error(`missing either pipeline name or regexp: ${targetPipelineName}, ${regexp}`)
        }
        acc.push([targetPipelineName, regexp])
        return acc
    }, [])

    const filesTouched = new Set(body.commits.reduce((acc, commit) => {
        acc = [...acc, ...commit.modified, ...commit.removed, ...commit.added]
        return acc
    }, []))

    const pipelinesToRun = new Set()
    for(const [targetPipelineName, regexp] of pipeline_name_regexp_pair) {
        if (Array.from(filesTouched).some(file => file.match(regexp))) {
            pipelinesToRun.add(targetPipelineName)
        }
    }

    console.log("Triggering pipelines: ", pipelinesToRun)

    let errors = [];
    const client = new CodePipelineClient();

    for (const pipelineName of pipelinesToRun.values()) {
        const params = {
            name: pipelineName
        };

        let result;
        try {
            result = await client.send()
        } catch (err) {
            errors.push({ request: params, error: err });
        }
    }

    if (errors.length > 0) {
        const response = {
            statusCode: 500,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                failed_requests: errors
            }, null, 2),
        };

        return callback(null, response);
    }

    const response = {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            input: event,
        }, null, 2),
    };

    return callback(null, response);
};